#lang racket

;; Copyright 2010 Michael M. Gorlick

;; Licensed under the Apache License, Version 2.0 (the "License");
;; you may not use this file except in compliance with the License.
;; You may obtain a copy of the License at
;;       http://www.apache.org/licenses/LICENSE-2.0
;; Unless required by applicable law or agreed to in writing, software
;; distributed under the License is distributed on an "AS IS" BASIS,
;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;; See the License for the specific language governing permissions and
;; limitations under the License.

;; This implementation borrows heavily from Racket v5.0/collects/racket/private/serialize.rkt
;; with numerous modifications to accommodate the serialized representations of Mischief mobile
;; closures and continuations.
;; Many of the comments are paraphrases of the Racket Reference, Section 12.11, "Serialization."

(require
 (only-in
  "baseline.rkt" ; For testing only.
  ENVIRON/TEST)
 "compile.rkt"
 "recompile.rkt"

 (only-in
  "persistent/vector.rkt"  ; For testing only.
  vector/build
  vector/update
  vector/persist?)

 (only-in
  "persistent/hash.rkt"
  ; For testing only.
  list/hash     
  hash/eq/null
  ; Required for deconstruction and reconstruction.
  hash/persist?
  hash/eq?
  hash/eqv?
  hash/length
  hash/equality
  hash/hash
  hash/root
  hash/construct)
 
 (only-in
  "persistent/set.rkt"
  ; For testing only.
  list/set
  set/eq/null
  ; Required for deconstruction and reconstruction
  set/persist?
  set/eq?
  set/eqv?
  set/length
  set/equality
  set/hash
  set/root
  set/construct)
 
 (only-in
  "persistent/tuple.rkt"
  ; For testing only.
  tuple
  list/tuple))

(provide 
 ;; Checks whether a value is serializable:
 serializable?
 
 ;; The two main routines:
 serialize
 deserialize
 
 serialized=?)

;; A serialized representation of a value v is a list
;; (<version> <structure-count> <structure-types> <n> <graph> <fixups> <final>) where:
;; <version> Version identifier of the representation given as a list (m) where m = 1, 2, ... is the version number
;; <structure-count> Unused by Mischief and always 0.
;; <structure-types> Unused by Mischief and always ().
;; <n> Length of the list <graph>
;; <graph> List of graph points. Each graph point is a serialized (sub)value to be used in the reconstruction of value v.
;; <fixups> List of pairs ((i . <serial>) ...) where each i = 0, 1, ... is an index into <graph> and <serial> is a specifier
;;          for the reconstruction of the value whose shape is given in graph point i.
;; <final> Serial specifier for the value v 

;; Graph points are either boxes whose contents specify the shape of a value to be constructed later:
;;   #&(v . N) denotes a vector N elements wide
;;   #&(b) denotes a box
;;   #&(h) denotes a hash table with eq? keys
;;   #&(h weak) denotes a hash table with weak eq? keys
;;   #&(h equal) denotes a hash table with equal? keys
;;   #&(h equal weak) denotes a hash table with weak equal? keys
;; OR values to be constructed immediately:
;;   boolean, number, character, interned symbol, or empty list, representing itself
;;   a string "..." representing an immutable character string
;;   a bytes sequence #"..." representing an immutable bytes sequence
;;   (? . i) at position j > i in the graph representing the value constructed for the i'th graph point within the graph
;;   (void) representing the value #<void>
;;   (u . "...") representing the mutable character string "..."
;;   (u . #"...") representing the mutable bytes sequence #"..."
;;   (c X Y), X, Y themselves representations,
;;      an immutable pair (x . y) where x, y is the value represented by X (Y) respectively
;;   (v X_0 ... X_n), X_0 ... X_n themselves representations, denotes
;;      an immutable vector #(x_0 ... x_n) where x_i is the value represented by X_i
;;   (v! X_0 ... X_n), X_0 ... X_n themselves representations, denotes
;;      a mutable vector #(x_0 ... x_n) where x_i is the value represented by X_i
;;   (b X), X itself a representation, denotes an immutable box #&x where x is the value represented by X
;;   (b! X), X itself a representation, denotes a mutable box #&x where x is the value represented by X
;;   (h [!-] (K . X) ...) where ! (-) represents a mutable (immutable) hash table respectively,
;;      with eq? keys and each (K . V), K and V themselves representations, is a key/value pair k/v where
;;      k (v) is the value represented by K (V) respectively
;;   (h [!-] equal (K . V) ...)
;;   (h [!-] weak  (K . V) ...)
;;   (h [!-] equal weak (K . V) ...) represent hash tables with equal?, weak, and equal? weak keys respectively and whose
;;      contents are the key/value pairs k/v represented by K/V.

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ;; serialize
  ;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (serializable? v)
  (or 
   (boolean? v)
   (null? v)
   (number? v)
   (char? v)
   (symbol? v)
   (string? v)
   (bytes? v)
   (vector/persist? v) ; Persistent functional vector.
   (hash/persist? v)   ; Persistent functional hash table.
   (set/persist? v)    ; Persistent functional set.
   (vector? v)         ; Covers Motile tuples as well since all tuples are vectors.
   (pair? v)
   (hash? v)
   (box? v)
   (void? v)
   (procedure? v)))

(define (mutable? o)
  (and
   (or 
    (box? o)
    (vector? o)
    (hash? o))
   (not (immutable? o))))

(define (for/each/vector v f)
  (let loop ((i 0)
             (n (vector-length v)))
    (when (< i n)
      (f (vector-ref v i))
      (loop (add1 i) n))))

;; Find a mutable object among those that contained in the current cycle.
(define (find-mutable v cycle/stack) 
  ; Walk back through cycle/stack to find something mutable.
  ; If we get to v without anything being mutable, then we're stuck.
  (let ([o (car cycle/stack)])
    (cond
      [(eq? o v)
       (error 'serialize "cannot serialize cycle of immutable values: ~e" v)]
      [(mutable? o) o]
      [else
       (find-mutable v (cdr cycle/stack))])))


(define (share-id share cycle)
  (+ (hash-count share)
     (hash-count cycle)))

;; Traverse v depth-first to identify cycles and sharing. Shared
;; object go in the `share' table, and mutable objects that are
;; cycle-breakers go in `cycle' table.
;; In each case, the object is mapped to a number that is
;; incremented as shared/cycle objects are discovered, so
;; when the objects are deserialized, build them in reverse
;; order.
(define (find-cycles-and-sharing v cycle share)
  (let ([cycle/candidates (make-hasheq)]  ;; Candidates for sharing
        [share/candidates (make-hasheq)]  ;; Candidates for cycles
        [cycle/stack null])               ;; Candidates for cycles but for finding mutables.
    (let loop ([v v])
      ;(display v) (newline) ; Debugging.
      (cond
        [(or (boolean? v)
             (number? v)
             (char? v)
             (symbol? v)
             (null? v)
             (void? v))
         (void)]

        [(hash-ref cycle v #f)
         ; We already know that this value is part of a cycle so ignore.
         (void)]

        [(hash-ref cycle/candidates v #f)
         ; We have seen this object before in our depth-first search hence it must be a member of a cycle.
         (let ([v/mutable
                (if (mutable? v) v (find-mutable v cycle/stack))])
           ; v/mutable will be used to break the cycle.
           (hash-set! cycle v/mutable (share-id share cycle))
           (unless (eq? v/mutable v)
             ;; As v and v/mutable are distinct v is potentially shared (refered to) by other objects.
             (hash-set! share v (share-id share cycle))))]

        [(hash-ref share v #f)
         ;; We already know that this value is shared so ignore.
         (void)]

        [(hash-ref share/candidates v #f)
         ; We've just learned that v is shared (refered to) by at least two other objects.
         (hash-set! share v (share-id share cycle))]

        [else
         (hash-set! share/candidates v #t)
         (hash-set! cycle/candidates v #t)
         (set! cycle/stack (cons v cycle/stack))
         (cond
           [(or (string? v) (bytes? v))
            (void)] ; No sub-structure.

           ; Persistent hash tables require particular care as the Mischief representation #('<hash/persist> <equality> <hash> <trie>)
           ; contains two Racket (not Mischief!) procedures, <equality> and <hash>, the key equality test and the key hash code
           ; generator respectively. We don't want the serializer to see either of those as it has no idea of what to do with them.
           ; The only element that requires deep inspection is the trie representing the contents of the persistent hash table.
           [(hash/persist? v) (loop (hash/root v))]

           ; Persistent sets require equal care as the Mischief representation is, with the exception of the
           ; tag in element 0, identical to that for persistent hash tables.
           [(set/persist? v) (loop (set/root v))]
           
            ; Accounts for tuples as well since all tuples are just vectors with a type tag in element 0.
           [(vector? v)
            ;(for-each loop (vector->list v))]
            (for/each/vector v loop)] ; Experimental. Will eliminating the conversion of vector to list speed things up?

           [(pair? v)
            (loop (car v)) 
            (loop (cdr v))]

           [(box? v)
            (loop (unbox v))]

           [(hash? v)
            (hash-for-each v (lambda (k v) (loop k) (loop v)))]
           
           [(procedure? v)
            (let ((descriptor (v #f #f))) ; All Mischief code/procedure/continuation descriptors are vectors.
              (loop descriptor))]

           [else (raise-type-error
                  'serialize
                  "serializable object"
                  v)])
         ; No more opportunities for this object to appear in a cycle as the depth-first search has returned.
         (hash-remove! cycle/candidates v)
         (set! cycle/stack (cdr cycle/stack))]))))

;; Generate the serialization description (known as a "serial") for the given object v.
;; v: an object for which we require a "serial"
;; share: a hash table of shared objects (objects refered to by two or more objects)
;; share?: #t if the share table should be consulted in constructing the "serial" and #f otherwise
(define (serialize-one v share share?)
  ; Return the "serial" descriptor of object v.
  (define (serial v share?)
    (cond
      [(or (boolean? v)
           (number? v)
           (char? v)
           (null? v))
       v] ; The "serial" of a boolean, number, char or null constant is itself.
      
      [(symbol? v) v] ; The "serial" of a symbol is itself.
      
      [(void? v) ; The "serial" of #<void> is (void).
       '(void)]
      
      [(and share? (hash-ref share v #f))
       => (lambda (id) (cons '? id))] ; The "serial" of a shared object is (? . id) where id is a share id.
      
      [(and (or (string? v) (bytes? v))
            (immutable? v))
       v] ; The "serial" of an immutable character string or bytes sequence is itself.
      
      [(or (string? v) (bytes? v))
       (cons 'u v)] ; The "serial" of a mutable character string or bytes sequence v is (u . v)
      
      [(vector/persist? v)
       ; A persistent vector v has the form #('<vector/persist> <count> <shift> <root> <tail>) where
       ; <count> and <shift> are integers >= 0,
       ; <root> is an ordinary mutable vector that is the root of the trie representing the persistent vector and
       ; <tail> is an ordinary mutable vector (of at most 32 elements) representing the current tail of the persistent vector.
       ; The serial representation is (V '<vector/persist> <count> <shift> <r> <t>) where <r> and <t> are the serial representations
       ; of the root and tail respectively.
       (cons 'V (map (lambda (x) (serial x #t)) (vector->list v)))]

      [(hash/persist? v)
       ; A persistent hash table v has the form #('<hash/persist> <equality> <hash> <root>) where:
       ;    <equality> and <hash> are Racket procedures for testing key equality and generating key hash codes respectively and
       ;    <root> is the root of the trie representing the hash table.
       (list
        'H
        (cond
          ((hash/eq?  v) 'eq)
          ((hash/eqv? v) 'eqv)
          (else          'equal))
        (serial (hash/root v) #t))]

      [(set/persist? v)
       ; A persistent set v has the form #('<set/persist> <equality> <hash> <root>) where:
       ;    <equality> and <hash> are the Racket procedures for testing set member equality and
       ;      generating member hash codes respectively and
       ;   <root> is the root of the trie representing the set.
       (list
        'S
        (cond
          ((set/eq?  v) 'eq)
          ((set/eqv? v) 'eqv)
          (else         'equal))
        (serial (set/root v) #t))]

      [(vector? v)
       ; "serial" for immutable vector x is (v s_0 ... s_N)  where s_i is the serial of element i of x.
       ; "serial" for mutable vector   x is (v! s_0 ... s_N) where s_i is the serial of element i of x.
       (cons (if (immutable? v) 'v 'v!)
             (map (lambda (x) (serial x #t)) (vector->list v)))]
      
      [(pair? v)
       ; The "serial" of a pair (x . y) is (c X . Y) where X, Y is the "serial" of x, y respectively. 
       (cons 'c
             (cons (serial (car v) #t)
                   (serial (cdr v) #t)))]
      
      [(box? v)
       ; The "serial" of an immutable box is (b . X) where X is the "serial" of the contents of box v.
       (cons (if (immutable? v) 'b 'b!) (serial (unbox v) #t))]
      
      [(procedure? v)
       (cons 'M (serial (v #f #f) #t))]

      [(hash? v)
       ; The "serial" of a hash table is (h <mutable> <modifiers> (X_1 . Y_1) ... (X_N . Y_N) where:
       ; <mutable> denotes an immutable - or mutable ! hash table
       ; <modifiers> is one of (), (equal), (weak), or (equal weak)
       ;  signifying eq?, equal?, eq? and weak, equal? and weak keys respectively.
       ; X_i, Y_i is the serial of key k_i and its value v_i respectively.
       (list* 'h
              (if (immutable? v) '- '!)
              (append
               (if (not (hash-eq? v)) '(equal) null)
               (if (hash-weak? v) '(weak) null))
              (hash-map v (lambda (k v) (cons (serial k #t) (serial v #t)))))]
      
      [else (error 'serialize "shouldn't get here")]))
  
  (serial v share?))

;; Return the encoding for a cyclic graph point for value v.
;; Only a vector, box, or hash table may contribute to a cycle.
(define (serial-shell v)
  (cond
    [(vector? v)
     (cons 'v (vector-length v))]
    [(box? v)
     'b]
    [(hash? v)
     (cons 'h (append
               (if (not (hash-eq? v)) '(equal) null)
               (if (hash-weak? v) '(weak) null)))])) 

(define (serialize v)
  (let ([share (make-hasheq)]
        [cycle (make-hasheq)])
    ; Traverse v to find cycles and sharing
    (find-cycles-and-sharing v cycle share)
    ;; To simplify, add all of the cycle records to shared (but retain the cycle information).
    (hash-for-each cycle (lambda (k v) (hash-set! share k v)))
    
    (let ([ordered ; List of all shared and cycle-breaking objects in ascending order by their respective share id.
           (map car
                (sort
                 (hash-map share cons) ; An association list ((o . id) ...) of object o with share id.
                 (lambda (a b) (< (cdr a) (cdr b)))))]) ; Sort by ascending share id.
      
      (let ([serializeds ; Issued in order of their appearance in the depth-first tour of v.
             (map
              (lambda (v)
                (if (hash-ref cycle v #f)
                    ; Box indicates cycle record allocation followed by normal serialization
                    (box (serial-shell v))
                    ; Otherwise, normal serialization
                    (serialize-one v share #f)))
              ordered)]

            [fixups ; All cycle-breaker serializations as an association list ((id . s) ...) where id is the serial id.
             (hash-map 
              cycle
              (lambda (v n) (cons n (serialize-one v share #f))))]
            
            [final (serialize-one v share #t)])

        (list '(2) ;; serialization-format version
              0    ; Number of distinct structure types. Unused in Mischief and just temporary.
              null ; List of distinct structure types. Unused in Mischief and just temporary.
              (length serializeds)
              serializeds ; The graph structure of the value.
              fixups
              final)))))

;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; deserialize
;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (make-hash/flags v)
  (cond
    [(null? v) (make-hasheq)]
    [(eq? (car v) 'equal)
     (if (null? (cdr v))
         (make-hash)
         (make-weak-hash))]
    [else (make-weak-hasheq)]))

(define-struct not-ready (shares fixup))

(define (lookup-shared! share n procedures)
  ;; The shared list is not necessarily in order of refereds before referees. A `not-ready' object
  ;;  indicates a reference before a value is ready,
  ;;  so we need to recur to make it ready. Cycles
  ;;  have been broken, though, so we don't run into
  ;;  trouble with an infinite loop here.
  (let ([value/shared (vector-ref share n)])
    (if (not-ready? value/shared)
        ; Reconstruct the shared value.
        (let* ([x (vector-ref (not-ready-shares value/shared) n)] ; x is shares[n]
               [reconstruction
                (if (box? x)
                    (deserial-shell (unbox x) (not-ready-fixup value/shared) n)
                    (deserialize-one x share procedures))])
          (vector-set! share n reconstruction)
          reconstruction)

        value/shared)))

(define (deserialize-one v share procedures)
  (let loop ([v v])
    (cond
      [(or (boolean? v)
           (number? v)
           (char? v)
           (symbol? v)
           (null? v))
       v]

      [(string? v) ; A standalone character string "..." denotes the equivalent immutable character string.
       (string->immutable-string v)]

      [(bytes? v)  ; A standalone bytes sequence #"..." denotes the equivalent immutable bytes sequence.
       (bytes->immutable-bytes v)]

      [else
       (case (car v)
         [(?) (lookup-shared! share (cdr v) procedures)] ; (? . i) where i is index into share

         [(void) (void)]                      ; (void)

         [(u) (let ([x (cdr v)])              ; (u . "...") or (u . #"..."). A mutable character string or bytes sequence respectively.
                (cond
                  [(string? x) (string-copy x)]
                  [(bytes? x) (bytes-copy x)]))]

         [(c) (cons (loop (cadr v)) (loop (cddr v)))]       ; (c x y). Pair (x . y).

         [(v) (apply vector-immutable (map loop (cdr v)))]  ; (v e_0 ... e_N). Immutable vector #(e_0 ... e_N).
         
         [(v!) (list->vector (map loop (cdr v)))]           ; (v! e_0 ... e_N). Mutable vector #(e_0 ... e_N).

         [(V) (list->vector (map loop (cdr v)))]            ; (V '<vector/persist> <count> <shift> <r> <t>) =>
                                                            ;     persistent vector #('<vector/persist> <count> <shift> <root> <tail>.

         [(H) ; (H <equality> <trie>). Persistent hash table.
          (let-values
              ([(equality hasher)
                 (case (cadr v)
                   ((eq)    (values eq?    eq-hash-code))
                   ((eqv)   (values eqv?   eqv-hash-code))
                   ((equal) (values equal? equal-hash-code)))])
            (hash/construct equality hasher (loop (caddr v))))]

         [(S) ; (S <equality> <trie>). Persistent set.
          (let-values
              ([(equality hasher)
                 (case (cadr v)
                   ((eq)    (values eq?    eq-hash-code))
                   ((eqv)   (values eqv?   eqv-hash-code))
                   ((equal) (values equal? equal-hash-code)))])
            (set/construct equality hasher (loop (caddr v))))]

         [(b) (box-immutable (loop (cdr v)))]               ; (b . x). Immutable box #&(x).

         [(b!) (box (loop (cdr v)))]                        ; (b! . x). Mutable box #&(x).

         ; (h [!-] ([equal][weak]) ((x . y) ...) where x is a serial id for a key and y a serial id for a value.
         [(h) (let ([al (map (lambda (p)                    
                               (cons (loop (car p))
                                     (loop (cdr p))))
                             (cdddr v))])
                (if (eq? '! (cadr v))
                    (let ([ht (make-hash/flags (caddr v))])
                      (for-each (lambda (p)
                                  (hash-set! ht (car p) (cdr p)))
                                al)
                      ht)
                    (if (null? (caddr v))
                        (make-immutable-hasheq al)
                        (make-immutable-hash al))))]

         [(M) ; Mischief code descriptor.
          (let* ((descriptor (loop (cdr v)))
                 (code (mischief/recompile/unit descriptor)))
            (when (or 
                   ;(code/reference/global?   descriptor)  ; References to global variables buried inside structures.
                   (code/lambda/inner?       descriptor)
                   (code/closure/inner?      descriptor)
                   (code/lambda/rest/inner?  descriptor)
                   (code/closure/rest/inner? descriptor))
              (hash-set! procedures code descriptor))
            code)]

         [else (error 'serialize "ill-formed serialization")])])))

(define (deserial-shell v fixup n)
  (cond
    [(pair? v)
     (case (car v)
       [(v)
        ; Vector 
        (let* ([m (cdr v)] ; Size of reconstructed vector.
               [reconstruction (make-vector m #f)])
          (vector-set!
           fixup
           n
           (lambda (v)
             (let loop ((i (sub1 m)))
               (unless (< i 0)
                 (vector-set! reconstruction i (vector-ref v i))
                 (loop (sub1 i))))))
          reconstruction)]             
             
;             (let loop ([i m])
;               (unless (zero? i)
;                 (let ([i (sub1 i)])
;                   (vector-set! reconstruction i (vector-ref v i))
;                   (loop i))))))

       [(h)
        ;; Hash table
        (let ([reconstruction (make-hash/flags (cdr v))])
          (vector-set!
           fixup n
           (lambda (h)
             (hash-for-each h (lambda (k v) (hash-set! reconstruction k v)))))
          reconstruction)])]

    [else
     (case v
       [(c)
        (let ([c (cons #f #f)])
          (vector-set! fixup n (lambda (p) (error 'deserialize "cannot restore pair in cycle")))
          c)]

       [(b)
        (let ([reconstruction (box #f)])
          (vector-set! fixup n (lambda (b) (set-box! reconstruction (unbox b))))
          reconstruction)])]))

(define (deserialize-with-map version l procedures)
  (let ([share/n (list-ref l 2)]
        [shares  (list-ref l 3)]
        [fixups  (list-ref l 4)]  ; Association list of ((<id> . <serial>) ...) in ascending order of share-id.
        [final   (list-ref l 5)])
    ; Create vector for sharing:
    (let* ([fixup (make-vector share/n #f)]
           [unready (make-not-ready (list->vector shares) fixup)]
           [share (make-vector share/n unready)])

      ; Deserialize into sharing array:
      (let loop ([n 0] [l shares])
        (unless (= n share/n)
          (lookup-shared! share n procedures)
          (loop (add1 n) (cdr l))))

      ; Fixup shell for graphs
      (for-each
       (lambda (n+v)
         (let ([v (deserialize-one (cdr n+v) share procedures)]
               [fixer (vector-ref fixup (car n+v))])
           (fixer v)))
       fixups)

      ; Deserialize final result. (If there's no sharing, then all the work is actually here.)
      (deserialize-one final share procedures))))

(define (extract-version l)
  (if (pair? (car l))
      (values (caar l) (cdr l))
      (values 0 l)))


;; Reconstitute the flat serialization into a live data structure closures and all.
;; flat: a serialization generate by (serialize ...)
;; globals: a Mischief global binding environment or #f. If #f then no closure embedded in flat will have its run-time stack
;;   properly reset and must be done, per-closure, prior to closure execution.
;; procedures?: If #f then return just the live data structure. If #t then return a pair (<live> . <procedures>) where
;;   <live> is the live data structure and <procedures> is an eq? hash table whose keys are the closures embedded in the live
;;   structure and whose values are the reconstituted closure descriptors embedded in the flat representation.
;;   The keys are effectively an enumeration of every closure contained in the live structure and the descriptors contain
;;   both the abstract assembly code for each closure as well as the the closed variables bindings for each closure.
(define (deserialize flat globals procedures?)
  (let-values ([(version flat) (extract-version flat)])
    (let* ((procedures (make-hasheq))
           (outcome    (deserialize-with-map version flat procedures))
           (frame      (and globals (vector #f globals)))
           (reframe    (and frame (cons frame null))))
      ; If there are Mischief procedures embedded somewhere in the deserialization then patch them up for execution.
      (when (positive? (hash-count procedures))
        (hash-for-each
         procedures
         (lambda (p d)
           ; Reset the bindings of each closure to their values at the time of serialization.
           (when (or (code/closure/inner? d) (code/closure/rest/inner? d))
             (p #f (code/closure/inner/bindings d)))
           ; If a global binding environment is given then supply each lambda and closure with the proper base frame
           ; (containing the global binding environment) for its run time stack.
           (when globals
             (p #f reframe)))))
      (if procedures?
          (cons outcome procedures)
          outcome))))

;; ----------------------------------------

(define (serialized=? l1 l2)
  (let-values ([(version1 l1) (extract-version l1)]
               [(version2 l2) (extract-version l2)])
    (let ([v1 (deserialize-with-map version1 l1)]
          [v2 (deserialize-with-map version2 l2)])
      (equal? v1 v2))))

;; Regression tests.

(define (test/serialize)
  (define (test/serialize/1)
    (let ((e (mischief/compile '(lambda () 13))))
      (display "test/serialize/1\n")
      (pretty-display (serialize e))))

  
  (define (test/serialize/2a)
    (let* ((e (mischief/compile
              '(let ((a 33))
                 (lambda (x) (+ x a x)))))
           (code (mischief/start e)))
      (display "test/serialize/2a\n")
      (pretty-display (serialize code))))
      
  (define (test/serialize/2b)
    (let* ((e (mischief/compile
              '(let ((a (list 11 22 33)))
                 (lambda (x) (append x a x)))))
           (code (mischief/start e)))
      (display "test/serialize/2b\n")
      (pretty-display (serialize code))))

  (define (test/serialize/3)
    (let* ((e (mischief/compile
               '(let ()
                  (define (factorial n) (if (= n 1) 1 (n * (factorial (sub1 n)))))
                  factorial)))
           (code (mischief/start e)))
      (display "test/serialize/3\n")
      (pretty-display (serialize code))))

  (test/serialize/1)
  (test/serialize/2a)
  (test/serialize/2b)
  (test/serialize/3))

(define (test/serialize/vector/persist)
  (define (test/serialize/vector/persist/1)
    (let ((e (mischief/compile
              '(let ((v (vector/build 100 (lambda (i) i))))
                 v))))
      (display "serialize/vector/persist/1\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))

  (define (test/serialize/vector/persist/2)
    (let ((e (mischief/compile
              '(let* ((a (vector/build 100 (lambda (i) i)))
                      (b (vector/update a 50 5000)))
                 (list a b)))))
      (display "serialize/vector/persist/2\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))

  (test/serialize/vector/persist/1)
  (test/serialize/vector/persist/2))

(define (test/deserialize/vector/persist)
  (define (test/deserialize/vector/persist/1)
    (let* ((v (vector/build 100 (lambda (i) i)))
           (e (mischief/compile
               '(let ((x (vector/build 100 (lambda (i) i))))
                  x)))
           (flat (serialize (mischief/start e))))
      (should-be 'deserialize/vector/persist/1 v (deserialize flat ENVIRON/TEST #f))))

  (define (test/deserialize/vector/persist/2)
    (let* ((a (vector/build 100 (lambda (i) i)))
           (b (vector/update a 50 5000))
           (e (mischief/compile
                '(let* ((a (vector/build 100 (lambda (i) i)))
                      (b (vector/update a 50 5000)))
                 (list a b))))
           (flat (serialize (mischief/start e))))
      (should-be 'deseriailze/vector/persist/2 (list a b) (deserialize flat ENVIRON/TEST #f))))


  (test/deserialize/vector/persist/1)
  (test/deserialize/vector/persist/2))

(define (test/serialize/hash/persist)
  (define (test/serialize/hash/persist/1)
    (let ((e (mischief/compile
              '(let ((h/26
                      (list/hash
                       hash/eq/null
                       '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
                           k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
                           u 21 v 22 w 23 x 24 y 25 z 26))))
                 h/26))))
      (display "serialize/hash/persist/1\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))
  
  (define (test/serialize/hash/persist/2)
    (let ((e (mischief/compile
              '(let* ((h/26
                       (list/hash
                        hash/eq/null
                        '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
                            k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
                            u 21 v 22 w 23 x 24 y 25 z 26)))
                      (h/21
                       (let loop ((h h/26) (vowels '(a e i o u)))
                         (if (null? vowels)
                             h
                             (loop (hash/remove h (car vowels)) (cdr vowels))))))
                 (list h/26 h/21 h/26)))))
      (display "serialize/hash/persist/2\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))

  (test/serialize/hash/persist/1)
  (test/serialize/hash/persist/2))

(define (test/deserialize/hash/persist)
  (define (test/deserialize/hash/persist/1)
    (let* ((gold (list/hash
                  hash/eq/null
                  '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
                      k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
                      u 21 v 22 w 23 x 24 y 25 z 26)))
           (e (mischief/compile
               '(let ((h/26
                       (list/hash
                        hash/eq/null
                        '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
                            k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
                            u 21 v 22 w 23 x 24 y 25 z 26))))
                  h/26)))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/hash/persist/1 gold plump)))

  (define (test/deserialize/hash/persist/2)
    (let* ((e (mischief/compile
              '(let* ((h/26
                       (list/hash
                        hash/eq/null
                        '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
                            k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
                            u 21 v 22 w 23 x 24 y 25 z 26)))
                      (h/21
                       (let loop ((h h/26) (vowels '(a e i o u)))
                         (if (null? vowels)
                             h
                             (loop (hash/remove h (car vowels)) (cdr vowels))))))
                 (list h/26 h/21 h/26))))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be
       'deserialize/hash/persist/2
       '(26 21 26 #t)
       (list
        (hash/length (car plump))
        (hash/length (cadr plump))
        (hash/length (caddr plump))
        (eq? (car plump) (caddr plump))))))

  (test/deserialize/hash/persist/1)
  (test/deserialize/hash/persist/2))

(define (test/serialize/set/persist)
  (define (test/serialize/set/persist/1)
    (let ((e (mischief/compile
              '(let ((alphabet (list/set set/eq/null '(a b c d e f g h i j k l m n o p q r s t u v w x y z))))
                alphabet))))
      (display "serialize/set/persist/1\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))
  
  (define (test/serialize/set/persist/2)
    (let ((e (mischief/compile
              '(let* ((alphabet (list/set set/eq/null '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))
                      (consonants
                       (let loop ((s alphabet) (vowels '(a e i o u)))
                         (if (null? vowels)
                             s
                             (loop (set/remove s (car vowels)) (cdr vowels))))))
                 (list alphabet consonants alphabet)))))
      (display "serialize/set/persist/2\n")
      (pretty-display (serialize (mischief/start e)))
      (display "\n")))

  (test/serialize/set/persist/1)
  (test/serialize/set/persist/2))

(define (test/deserialize/set/persist)
  (define (test/deserialize/set/persist/1)
    (let* ((gold (list/set set/eq/null '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))
           (e (mischief/compile
               '(let ((alphabet (list/set set/eq/null '(a b c d e f g h i j k l m n o p q r s t u v w x y z))))
                  alphabet)))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/set/persist/1 gold plump)))

  (define (test/deserialize/set/persist/2)
    (let* ((e (mischief/compile
              '(let* ((alphabet (list/set set/eq/null '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))
                      (consonants
                       (let loop ((s alphabet) (vowels '(a e i o u)))
                         (if (null? vowels)
                             s
                             (loop (set/remove s (car vowels)) (cdr vowels))))))
                 (list alphabet consonants alphabet))))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be
       'deserialize/set/persist/2
       '(26 21 26 #t)
       (list
        (set/length (car plump))
        (set/length (cadr plump))
        (set/length (caddr plump))
        (eq? (car plump) (caddr plump))))))

  (test/deserialize/set/persist/1)
  (test/deserialize/set/persist/2))

(define (test/deserialize/tuple)
  (define (test/deserialize/tuple/1)
    (let* ((gold (list/tuple '(a b c d e f g h i j k l m n o p q r s t u v w x y z)))
           (e (mischief/compile
               '(let ((alphabet (list/tuple '(a b c d e f g h i j k l m n o p q r s t u v w x y z))))
                  alphabet)))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/tuple/1 gold plump)))
  
    (define (test/deserialize/tuple/2)
    (let* ((gold (cons (tuple 'a 'e 'i 'o 'u) (list/tuple '(b c d f g h j k l m n p q r s t v w x y z))))
           (e (mischief/compile
               '(let ((alphabet (list/tuple '(a b c d e f g h i j k l m n o p q r s t u v w x y z))))
                  (tuple/partition alphabet (lambda (letter) (memq letter '(a e i o u)))))))
           (flat (serialize (mischief/start e)))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/tuple/2 gold plump)))
  
  (test/deserialize/tuple/1)
  (test/deserialize/tuple/2))

(define (test/deserialize)
  (define (test/deserialize/1a)
    (let* ((e (mischief/compile
               '(let ((a (list 11 22 33)))
                  (lambda (x) (append x a x)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/1a '(a b 11 22 33 a b) (plump rtk/RETURN '(a b)))))

  (define (test/deserialize/1b)
    (let* ((e (mischief/compile
               '(let ((a (lambda () (list 11 22 33)))
                      (b '#(lambda 0 #(constant/generate 99)))) ; A fake piece of Mischief code.
                  (lambda (x) (append (list b) (a) x)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump+ (deserialize flat ENVIRON/TEST #t)))
      ;(pretty-display (cdr plump+))
      (should-be
       'deserialize/1b
       '(#(lambda 0 #(constant/generate 99)) 11 22 33 a b)
       ((car plump+) rtk/RETURN '(a b)))))

  (define (test/deserialize/2)
    (let* ((e (mischief/compile
               '(let ()
                  (define (factorial n) (if (= n 1) 1 (* n (factorial (sub1 n)))))
                  factorial)))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      ;(pretty-display flat)
      (should-be 'deserialize/2 120 (plump rtk/RETURN 5))))

  (define (test/deserialize/3)
    (let* ((e (mischief/compile
              '(lambda (a b) (+ a b))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/3 28 (plump rtk/RETURN 19 9))))

 (define (test/deserialize/4)
    (let* ((e (mischief/compile
              '(lambda (a b c) (list a c b))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/4 '(19 12 9) (plump rtk/RETURN 19 9 12))))

  ; Deserializing a lambda expression with > 3 arguments.
  (define (test/deserialize/5)
    (let* ((e (mischief/compile
              '(lambda (a b c d e f) (list a c e b d f))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/5 '(10 30 50 20 40 60) (plump rtk/RETURN 10 20 30 40 50 60))))
  
  ; Closures embedded in data structures.
  (define (test/deserialize/6)
    (let* ((e (mischief/compile
               '(lambda ()
                  (define (even? n)
                    (if (= n 0) #t (odd? (- n 1))))
                  (define (odd? n)
                    (if (= n 0) #f (even? (- n 1))))
                  (let ((v (vector even? odd?)))
                    (list
                     ((vector-ref v 0) 12) ; even?
                     ((vector-ref v 0) 3)  ; even?
                     ((vector-ref v 1) 17) ; odd?
                     ((vector-ref v 1) 8)  ; odd?
                     )))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/6 '(#t #f #t #f) (plump rtk/RETURN))))

  ; Closure with a single rest argument.
  (define (test/deserialize/7a)
    (let* ((e (mischief/compile
               '(let ((a 12) (b 13) (c (vector 'a 'b)))
                  (lambda rest (list b c a rest)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/7a '(13 #(a b) 12 (100 200 300)) (plump rtk/RETURN 100 200 300))))

  ; Closure with two arguments, one being a rest argument.
  (define (test/deserialize/7b)
    (let* ((e (mischief/compile
               '(let ((a 12) (b 13) (c (vector 'a 'b)))
                  (lambda (x . rest) (list x b c a rest)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/7b '(100 13 #(a b) 12 (200 300)) (plump rtk/RETURN 100 200 300))))
    
  ; Closure with three arguments, one being a rest argument.
  (define (test/deserialize/7c)
    (let* ((e (mischief/compile
               '(let ((a 12) (b 13) (c (vector 'a 'b)))
                  (lambda (x y . rest) (list x y b c a rest)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/7c '(100 200 13 #(a b) 12 (300)) (plump rtk/RETURN 100 200 300))))

  ; Closure with four arguments, one being a rest argument.
  (define (test/deserialize/7d)
    (let* ((e (mischief/compile
               '(let ((a 12) (b 13) (c (vector 'a 'b)))
                  (lambda (x y z . rest) (list x y z b c a rest)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/7d '(100 200 300 13 #(a b) 12 (750)) (plump rtk/RETURN 100 200 300 750))))
  
  ; Closure with five arguments, one being a rest argument.
  (define (test/deserialize/7e)
    (let* ((e (mischief/compile
               '(let ((a 12) (b 13) (c (vector 'a 'b)))
                  (lambda (w x y z . rest) (list w x y z b c a rest)))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/7e '(100 200 300 750 13 #(a b) 12 (99 88)) (plump rtk/RETURN 100 200 300 750 99 88))))


  ; lambda with a single rest argument.
  (define (test/deserialize/8a)
    (let* ((e (mischief/compile
               '(lambda rest rest)))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/8a '(100 200 300) (plump rtk/RETURN 100 200 300))))

  ; lambda with two arguments, one being a rest argument.
  (define (test/deserialize/8b)
    (let* ((e (mischief/compile
               '(lambda (x . rest) (list x rest))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/8b '(100 (200 300)) (plump rtk/RETURN 100 200 300))))
  
  ; lambda with three arguments, one being a rest argument.
  (define (test/deserialize/8c)
    (let* ((e (mischief/compile
               '(lambda (x y . rest) (list y x rest))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/8c '(200 100 (300)) (plump rtk/RETURN 100 200 300))))
 
  ; lambda with four arguments, one being a rest argument.
  (define (test/deserialize/8d)
    (let* ((e (mischief/compile
               '(lambda (x y z . rest) (list y z x rest))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/8d '(200 300 100 (750 200)) (plump rtk/RETURN 100 200 300 750 200))))

  ; lambda with five arguments, one being a rest argument.
  (define (test/deserialize/8e)
    (let* ((e (mischief/compile
               '(lambda (w x y z . rest) (list w y z x rest))))
           (code (mischief/start e))
           (flat (serialize code))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (should-be 'deserialize/8e '(100 300 750 200 (900 baseball)) (plump rtk/RETURN 100 200 300 750 900 'baseball))))   

  (test/deserialize/1a)
  (test/deserialize/1b)
  (test/deserialize/2)
  (test/deserialize/3)
  (test/deserialize/4)
  (test/deserialize/5)
  (test/deserialize/6)
  (test/deserialize/7a)
  (test/deserialize/7b)
  (test/deserialize/7c)
  (test/deserialize/7d)
  (test/deserialize/7e)
  (test/deserialize/8a)
  (test/deserialize/8b)
  (test/deserialize/8c)
  (test/deserialize/8d)
  (test/deserialize/8e))

(define (test/global/values)
  (define (test/global/values/1)
    (let* ((e (mischief/compile
               '(let ((h (hash/new hash/eq/null 'cons cons '+ +))
                      (f (lambda (table) ((hash/ref table 'cons #f) 33 99))))
                  (f h))))
           (flat (serialize e))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (pretty-display flat)
      (pretty-display (mischief/start plump))))

  (define (test/global/values/2)
    (let* ((table (mischief/compile
                   '(let () (hash/new hash/eq/null 'cons cons '+ +))))
           (flat (serialize (mischief/start table))))
      (pretty-display flat)))

  (define (test/global/values/3)
    (let* ((e (mischief/compile '(let () (lambda (table) ((hash/ref table 'cons #f) 33 99)))))
           (f (mischief/start e))
           (flat '((2) 0 () 0 () () (H eq (v! 256 (v! 132 (c cons M v! reference/global cons) (c + M v! reference/global +))))))
           (plump (deserialize flat ENVIRON/TEST #f)))
      (pretty-display plump)
      (pretty-display (f #f #f))
      (pretty-display (f rtk/RETURN plump))))

  (test/global/values/1)
  (test/global/values/2)
  (test/global/values/3))

(define (test/global)
  (define (test/global/1)
    (let ((e (mischief/compile '(let ((x cons)) (x 33 99)))))
      (pretty-display (mischief/start e))))

  (test/global/1))