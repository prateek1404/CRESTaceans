(import srfi-13)
(import serf/htmlparser)
(import serf/abdera)
(import serf/wordcount)

(import oo)
(import serf/object)
(import serf/http/response)
(import serf/http/entity)
(import serf/uri)
(import serf/json)
(import serf/time)
(import serf/fiber)
(import serf/mailbox)
(import serf/message)
(import serf/imposter)

(define (hg counter)
  (let* (
    (imposter/inbox (make <mailbox>))
    (imposter (object/forge <serf/imposter> (this-log) imposter/inbox))
    (imposter/loop (fiber/new (lambda () (imposter/dispatch imposter))))
    (path (format "/static/feeds/espn/~d.xml" counter))
    (uri (uri/new "http" "localhost" 8080 path))
    (reply (make <mailbox>))
   )
   (fiber/start imposter/loop)
   (! (@ imposter/inbox '/http/get) (list uri #f #f) :no-metadata: (@ reply '/http/response) counter)
   (let ((m (? reply 250 #f)))
    (if m
     (let* ((response (:message/body m))
            (response-body (http/response/entity response))
            (response-body-str (http/entity/string response-body))
            (feed (abdera/parse response-body-str))
            (feed-list '())
            (word-count (generate-wordcount (parse-feed-content feed) 3 2))
            (wc-list '())
           )
      (define (feed-map e)
        (list (cons "type" "message")
              (cons 'label (abdera/entry/title e))
              (cons 'text (abdera/entry/content e))
              (cons 'sent (utc/string (abdera/entry/updated e)))
        )
      )
      (define (nc-map e) (list (cons 'name (car e)) (cons 'count (cdr e))))
      (set! feed-list (list (cons "label" "label") (cons 'items (list->vector (map feed-map (abdera/feed/list feed))))))
      (display (json/string feed-list))
      (display "\n")
      (display "\n")
      (set! wc-list (list (cons 'items (list->vector (map nc-map word-count)))))
      (display (json/string wc-list))
      (display "\n")
     )
     (display "No response bud.\n"))
   )
   (set! counter (+ counter 1)))
)

(define (parse-feed feed)
  (let* ((pf (abdera/parse feed))
         (pl (abdera/feed/list pf))
         (pm (map abdera/entry/content pl)))
  (string-join pm)))

(define (parse-feed-content feed)
  (let* ((pl (abdera/feed/list feed))
         (pm (map abdera/entry/content pl)))
  (string-join pm)))

(define (generate-wordcount s l c)
  (let* ((hp (htmlparser/parse s))
         (ht (htmlparser/get-text hp))
         (wc (wordcount/list ht))
        )
   (topwc wc l c)
  )
)

(define pf (abdera/parse :gpo-atom-feed:))
(define pl (abdera/feed/list pf))
;(define pt (abdera/entry/content (car pl)))
(define pm (map abdera/entry/content pl))
(define ps (string-join pm))

(define hp (htmlparser/parse ps))
(define ht (htmlparser/get-text hp))

(define wc (wordcount/list ht))

;(define (top5 list)
;  (if (> (cdr list) 5) list))

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

(display (topwc wc 3 15))
(display "\n")
