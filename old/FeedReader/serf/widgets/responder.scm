; curl http://localhost:8081/widget/manager/move -d "{\"id\":\"W_3\",\"x\":500}"
; curl http://localhost:8081/widget/manager/link -d "{\"from\":\"W_1\",\"to\":\"W_3\",\"type\":\"link\"}"
; curl http://localhost:8081/widget/manager/create -d "{\"type\":\"widget\",\"id\":\"W_3\",\"title\":\"QR Code\",\"x\":-333,\"y\":299,\"width\":242,\"height\":17,\"color\":\"blue\",\"host\":\"Peer 2\"}"
; curl http://localhost:8081/widget/maps/maps.json
; curl http://localhost:8081/widget/tagcloud/tagcloud.json

(import srfi-13)
(import serf/htmlparser)
(import serf/abdera)
(import serf/wordcount)

(import oo)
(import serf/object)
(import serf/http/request)
(import serf/http/response)
(import serf/http/entity)
(import serf/uri)
(import serf/json)
(import serf/time)
(import serf/fiber)
(import serf/mailbox)
(import serf/message)
(import serf/imposter)
(import serf/sham)

(import hashtable)

(define (parse-feed feed)
  (let* ((pf (abdera/parse feed))
         (pl (abdera/feed/list pf))
         (pm (map abdera/entry/content pl)))
  (string-join pm)))

(define (parse-feed-content feed)
  (let* ((pl (abdera/feed/list feed))
         (pm (map abdera/entry/content pl))
         (pt (map abdera/entry/title pl)))
  (string-join (append pm pt))))

(define (generate-wordcount s l c)
  (let* ((hp (htmlparser/parse s))
         (ht (htmlparser/get-text hp))
         (wc (wordcount/list ht))
        )
   (topwc wc l c)
  )
)

(define (alist-filter list filter)
 (let loop ((pairs list) (outcome '()))
  (cond
   ((null? pairs) outcome)
    (else
     (if (filter (car pairs))
       (loop (cdr pairs) (cons (car pairs) outcome))
       (loop (cdr pairs) outcome))))))

(define (topwc s wordlen count)
  (alist-filter s (lambda (x)
    (and (> (string-length (car x)) wordlen) (>= (cdr x) count)))))

(define (widget-list key value) (hashtable->alist value))

(define (widget-url title)
   (cond ((string-ci=? "RSS Reader" title) "/widget/feed/rss.json")
         ((string-ci=? "Tag Cloud" title) "/widget/tagcloud/tagcloud.json")
         ((string-ci=? "QR Code" title) "/widget/qrcode/qrcode.json")
         ((string-ci=? "Mirror" title) "/widget/mirror/mirror.json")
         ((string-ci=? "URL Selector" title) "/widget/url/url.json")
         (else "")
   )
)

(define (widget/test host)
  (let ((peer (object/forge <serf/peer> host 8081 :serf-sandbox-path:))
        (counter 1)
        (linkid 0)
        (feed-url (uri/new "http" "localhost" 8080 (format "/static/feeds/espn/")))
        (current-widgets (make-hashtable string-ci=?)))

    (define (responder/hello sham origin uri request response)
      (http/response/entity! response (format "Hello! Nice to hear from you again [~d]." counter))
      (set! counter (+ counter 1)))

    (define (responder/feed sham origin uri request response)
      (let* (
        (dest-uri (uri/new (string-append (uri/ascii feed-url) (format "~d.xml" counter))))
        (reply (make <mailbox>))
       )
       (! (@ (peer/dispatch peer) '/http/get) (list dest-uri #f #f) :no-metadata: (@ reply '/http/response) counter)
       (let ((m (? reply 250 #f)))
        (if m
         (let* ((feed-response (:message/body m))
                (response-body (http/response/entity feed-response))
                (response-body-str (http/entity/string response-body))
                (feed (abdera/parse response-body-str))
                (feed-list '())
                (item-count 0)
               )
          (define (feed-map e)
            (set! item-count (+ item-count 1))
            (list (cons "type" "message")
                  (cons 'id (format "node~d" item-count))
                  (cons 'label (abdera/entry/title e))
                  (cons 'text (abdera/entry/content e))
                  (cons 'sent (utc/string (abdera/entry/updated e)))
            )
          )
          (set! feed-list (list (cons "label" "label") (cons 'items (list->vector (map feed-map (abdera/feed/list feed))))))
          (http/response/entity! response (json/string feed-list))
        )))
      (set! counter (+ counter 1))))
  
    (define (responder/tagcloud sham origin uri request response)
      (let* (
        (path (format "/static/feeds/espn/~d.xml" counter))
        (dest-uri (uri/new "http" "localhost" 8080 path))
        (reply (make <mailbox>))
       )
       (! (@ (peer/dispatch peer) '/http/get) (list dest-uri #f #f) :no-metadata: (@ reply '/http/response) counter)
       (let ((m (? reply 250 #f)))
        (if m
         (let* ((feed-response (:message/body m))
                (response-body (http/response/entity feed-response))
                (response-body-str (http/entity/string response-body))
                (feed (abdera/parse response-body-str))
                (word-count (generate-wordcount (parse-feed-content feed) 3 2))
                (wc-list '())
               )
          (define (nc-map e) (list (cons 'name (car e)) (cons 'count (cdr e))))
          (set! wc-list (list (cons 'items (list->vector (map nc-map word-count)))))
          (http/response/entity! response (json/string wc-list))
        )))
    ))

    (define (responder/manager sham origin uri request response)
      (let* (
        (req-body (http/entity/string (http/request/entity request)))
        ;(req-body :json-test:)
        (req-uri (http/request/uri request))
       )
      (display req-uri)
      (display "\n")
      (let* ((req-val (json/translate req-body)))
         (cond ((string-suffix-ci? "/create" req-uri)
                (display req-val)
                (display "\n")
                (let* (
                  (table (make-hashtable string-ci=?))
                  )
                  (for-each (lambda (v) (hashtable/put! table (car v) (cdr v))) req-val)
                  (let* ((wid (hashtable/get table "id"))
                         (title (hashtable/get table "title"))
                         (type-url (widget-url title)))
                  (hashtable/put! table "url" type-url)
                  (hashtable/put! current-widgets wid table))
                  (http/response/entity! response (format "Hello! Nice to hear from you again [~d]." counter))
                ))
               ((string-suffix-ci? "/link" req-uri)
                (let* (
                  (table (make-hashtable string-ci=?))
                  )
                  (for-each (lambda (v) (hashtable/put! table (car v) (cdr v))) req-val)
                  (hashtable/put! current-widgets (string-join (list "link" (number->string linkid))) table)
                  (set! linkid (+ linkid 1))
                  (http/response/entity! response (format "Hello! Nice to hear from you again [~d]." counter))
                )
               )
               ((string-suffix-ci? "/move" req-uri)
                (let* (
                  (table (make-hashtable string-ci=?))
                  )
                  (for-each (lambda (v) (hashtable/put! table (car v) (cdr v))) req-val)
                  (let* ((wid (hashtable/get table "id"))
                         (cur-val (hashtable/get current-widgets wid)))
                  (define (widget-list-update k v)
                          (hashtable/put! cur-val k v)
                  )
                  (hashtable/for-each widget-list-update table)
                  (http/response/entity! response (format "Hello! Nice to hear from you again [~d]." counter))
                ))
               )
               (else (display (format "Unknown URI: ~s" req-url))))
      )
      )
    )

    (define (responder/qrcode sham origin uri request response)
      (let* (
        (host-hdr (http/request/header request "Host"))
        (demo-uri (format "http://~a/static/dojo/demo/demo.html" (cdr host-hdr)))
       )
       (http/response/entity! response (json/string (list (cons 'items (list->vector(list (list (cons "url" demo-uri))))))))))

    (define (responder/urlsel sham origin uri request response)
      (let* (
        (host-hdr (http/request/header request "Host"))
        (demo-uri (format "http://~a/static/dojo/demo.html" (cdr host-hdr)))
       )
       (http/response/entity! response (json/string (list (cons 'items (list->vector(list (list (cons "url" (uri/ascii feed-url)))))))))))

    (define (responder/maps sham origin uri request response)
       (http/response/entity! response (json/string (list (cons 'items (list->vector(hashtable/map widget-list current-widgets)))))))

    (sham/register (peer/sham peer) "/widget/manager/*"   responder/manager)
    (sham/register (peer/sham peer) "/widget/maps/*"   responder/maps)

    (sham/register (peer/sham peer) "/widget/feed/*"    responder/feed)
    (sham/register (peer/sham peer) "/widget/tagcloud/*"   responder/tagcloud)
    (sham/register (peer/sham peer) "/widget/qrcode/*"   responder/qrcode)
    (sham/register (peer/sham peer) "/widget/url/*"   responder/urlsel)

    peer))

(define :json-test: "{\"type\":\"widget\",\"id\":\"W_3\",\"title\":\"QR Code\",\"x\":-333,\"y\":299,\"width\":242,\"height\":17,\"color\":\"blue\",\"host\":\"Peer 1\"}")
