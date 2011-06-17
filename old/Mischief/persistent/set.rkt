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

;; Contact: mgorlick@acm.org

(require "trie.rkt")

(provide
 setpersist?
 set/eq/null
 set/eqv/null
 set/equal/null
 set/eq?
 set/eqv?
 set/equal?
 
 list/set
 set/new
 set/fold
 set/length
 set/empty?
 set/list
 set/cons
 set/remove
 set/contains?
 set/car
 set/cdr
 set/map
 set/subset?
 set/union
 set/intersection
 set/difference
 set/filter
 set/partition
 
 ; Exported for the sake of serialize/deserialize.
 set/equality
 set/hash
 set/root
 set/construct)
 

;; A persistent unordered set is a four element vector v:
;; v[0] - the literal symbol setpersist
;; v[1] - the key equality test, one of eq?, eqv?, or equal?
;; v[2] - the key hash function, one of eq-hash-code, eqv-hash-code, or equal-hash-code
;; v[3] - the top level trie, the root of the set.
(define-accessor set/equality  1)
(define-accessor set/hash      2)
(define-accessor set/root      3)

(define (set/construct equality? hash root)
  (vector 'setpersist equality? hash root))

(define set/eq/null    (set/construct eq?    eq-hash-code    trie/empty))
(define set/eqv/null   (set/construct eqv?   eqv-hash-code   trie/empty))
(define set/equal/null (set/construct equal? equal-hash-code trie/empty))

(define (setpersist? s)
  (and
   (vector? s)
   (eq? (vector-ref s 0) 'setpersist)
   (= (vector-length s) 4)))

(define (set/eq? s)    (eq? (set/equality s) eq?))
(define (set/eqv? s)   (eq? (set/equality s) eqv?))
(define (set/equal? s) (eq? (set/equality s) equal?))

(define (list/set s elements)
  (let ((equality? (set/equality s))
        (hasher    (set/hash s)))
    (let loop ((elements elements)
               (t (set/root s)))
      (if (null? elements)
          (set/construct equality? hasher t)
          (let ((key (car elements)))
            (loop (cdr elements) (trie/key/with equality? hasher t key #t (hasher key) 0)))))))

(define (set/new s . rest)
  (list/set s rest))

(define (set/fold s f seed)
  (pairs/fold (lambda (pair seed) (f (car pair) seed)) seed (set/root s)))

(define (set/length s)
  (pairs/count (set/root s)))

(define (set/empty? s)
  (eq? (set/root s) trie/empty))

(define (set/list s)
  (pairs/fold (lambda (pair seed) (cons (car pair) seed)) null (set/root s)))

(define (set/cons s element)
  (let* ((equality? (set/equality s))
         (hasher    (set/hash s))
         (t (trie/key/with equality? hasher (set/root s) element #t (hasher element) 0)))
    (set/construct equality? hasher t)))

(define (set/remove s element)
  (let* ((equality? (set/equality s))
         (hasher (set/hash s))
         (t (trie/without equality? (set/root s) element (hasher element) 0)))
    (if (eq? t (set/root s))
        s
        (set/construct equality? hasher t))))

(define (set/contains? s element)
  (if (trie/get (set/equality s) (set/root s) element ((set/hash s) element) 0)
      #t
      #f))

(define (set/car s)
  (let ((t (set/root s)))
    (if (eq? t trie/empty)
        (error 'set/car "car of empty set")
        (car (trie/car t)))))

(define (set/cdr s)
  (let ((t (set/root s)))
    (if (eq? t trie/empty)
        (error 'set/cdr "cdr of empty set")
        (set/construct (set/equality s) (set/hash s) (trie/cdr t)))))

(define (set/map s f)
  (let ((equality? (set/equality s))
        (hasher    (set/hash s)))
    (define (map pair seed)
      (let ((x (f (car pair))))
        (trie/key/with equality? hasher seed x #t (hasher x) 0)))

    (set/construct
     equality?
     hasher
     (pairs/fold map trie/empty (set/root s)))))

;; Returns #t if set beta is a subset of set alpha and #f otherwise.
(define (set/subset? alpha beta)
  (let ((root      (set/root alpha))
        (equality? (set/equality alpha))
        (hasher    (set/hash alpha)))
    (call/cc
     (lambda (k)
       (pairs/fold
        ; Continue in the fold until we exhaust beta or prove that beta is not a subset.
        (lambda (pair seed)
          (let ((element (car pair)))
            (if (trie/get equality? root element (hasher element) 0)
                #t
                (k #f)))) ; Blow out of the fold immediately.
        #t                   ; Seed.
        (set/root beta)))))) ; Source of pairs.

;; Returns the union of sets alpha and beta.
;; The resulting set is defined with the equality? and hash functions of set alpha.
(define (set/union alpha beta)
  (let* ((equality? (set/equality alpha))
         (hasher    (set/hash alpha))
         (union
          (pairs/fold

           (lambda (pair t)
             (let ((element (car pair)))
               (trie/key/with equality? hasher t element #t (hasher element) 0)))

           (set/root alpha)
      
           (set/root beta))))
    (set/construct equality? hasher union)))

;; Returns the intersection of sets alpha and beta.
;; The resulting set is defined with the equality? and hash functions of set alpha.
(define (set/intersection alpha beta)
  (let* ((equality? (set/equality alpha))
         (hasher    (set/hash alpha))
         (root      (set/root alpha))
         (intersection
          ; Test each element of beta for membership in alpha and if present add to intersection.
          ; Return a root trie containing the intersection.
          (pairs/fold
           
           (lambda (pair t)
             (let* ((element (car pair)) ; From beta.
                    (hash (hasher element)))
               (if (trie/get equality? root element hash 0)
                   ; The element from beta is a member of alpha so generate a successor trie containing it.
                   (trie/key/with equality? hasher t element #t hash 0)
                   ; The element from beta is not a member of alpha so leave the trie alone.
                   t)))

           trie/empty ; Seed trie of intersection.
                           
           (set/root beta)))) ; Source of pairs for fold

    (set/construct equality? hasher intersection)))


;; Return the subset, S, of alpha such that no member of S is also a member of beta.
(define (set/difference alpha beta)
  (let ((equality? (set/equality alpha))
        (hasher    (set/hash alpha)))
    (let ((difference
           (pairs/fold
            
            (lambda (pair t)
              (let ((element (car pair))) ; From beta.
                (trie/without equality? t element (hasher element) 0)))
            
            (set/root alpha) ; Seed.
            
            (set/root beta))))
      (set/construct equality? hasher difference))))

;; Return the subset of s such that for all elements x in s (f x) holds.
(define (set/filter s f)
  (let ((equality? (set/equality s))
        (hasher    (set/hash s)))
    (let ((subset
           (pairs/fold
            (lambda (pair t)
              (let ((element (car pair)))
                (if (f element)
                    (trie/key/with equality? hasher t element #t (hasher element) 0)
                    t)))
            trie/empty
            (set/root s))))
      (set/construct equality? hasher subset))))

;; Partition set s into two disjoint subsets A and B of s where f holds for all members of A
;; and f does not hold for all members of B.
;; Returns the partition as a pair (A . B).
(define (set/partition s f)
  (let ((equality? (set/equality s))
        (hasher    (set/hash s)))
    (let ((final
           (pairs/fold
            (lambda (pair partition)
              (let* ((element (car pair))
                     (i (if (f element) 0 1)))
                (vector-set!
                 partition i
                 (trie/key/with equality? hasher (vector-ref partition i) element #t (hasher element) 0))
                partition))
            (vector trie/empty trie/empty)
            (set/root s))))
      (cons
       (set/construct equality? hasher (vector-ref final 0))
       (set/construct equality? hasher (vector-ref final 1))))))

;; Testing ephemera.

;(define s/26
;  (list/set
;   set/eq/null
;   '(a 1 b 2 c 3 d 4 e 5 f 6 g 7 h 8 i 9 j 10
;     k 11 l 12 m 13 n 14 o 15 p 16 q 17 r 18 s 19 t 20
;     u 21 v 22 w 23 x 24 y 25 z 26)))
;
;(define (set/car/test s)
;  (let loop ((s s)
;             (outcome null))
;    (if (set/empty? s)
;        outcome
;        (loop (set/cdr s) (cons (set/car s) outcome)))))
;
;(define (set/map/test s)
;  (set/map
;   s
;   (lambda (element)
;     (if (symbol? element) 999 element))))
;  