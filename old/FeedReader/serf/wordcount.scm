(define (wordcount/list s)
  (let ((table (make-hashtable string-ci=?)))
    (for-each (lambda (word)
    (let ((n (hashtable/get table word #f)))
       (hashtable/put! table word (if n (+ 1 n) 1))))
    (string-tokenize s))
   (hashtable->alist table)
 ))
