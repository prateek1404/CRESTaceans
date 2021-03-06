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

;; A collection of utility functions for dissecting Scheme forms.

(provide
 ; (quote ...)
 quote?
 quotation
 ; (if <test> <then> <else>)
 if?
 if/test
 if/then
 if/else
 ; (when <test> <thens>)
 when?
 when/test
 when/thens
 ; (unless <test> <elses>)
 unless?
 unless/test
 unless/elses
 ; (begin <expressions>)
 begin?
 begin/expressions
 ; (cond <clauses>)
 cond?
 cond/clauses
 ; (lambda <parameters> <body>)
 lambda?
 lambda/parameters
 lambda/body
 ; (and <expressions>)
 and?
 ; (or <expressions>)
 or?
 ; (let <bindings> <body>)
 let?
 let/bindings
 let/named/bindings
 let/named/body
 let/body
 let/binding/symbol
 let/binding/expression
 let/bindings/variables
 let/bindings/expressions

 ; quasiquotation, as in, `(foo ,bar @,tail).
 quasiquote?
 unquote?
 unquote-splicing?
 
 ; Internal set!
 setter?
 setter/tag
 setter/target
 setter/value
 
 ; Macros.
 definition/macro?
 
 ; Weird internal letrec/set!
; letrec/setter?
; letrec/setter/tag
; letrec/setter/target
; letrec/setter/value
 
 ; Is the form a symbol?
 variable?

 ; Does a form have the expected structure?
 shape)

(define (quote? e) (eq? (car e) 'quote))
(define (quotation e) (cadr e))

(define (if? e) (eq? 'if (car e)))
(define (if/test e) (cadr e))
(define (if/then e) (caddr e))
(define (if/else e) (cadddr e))

(define (when? e) (eq? 'when (car e)))
(define (when/test e) (cadr e))
(define (when/thens e)
  (let ((thens (cddr e)))
    (if (null? thens)
        (error "empty <thens> in (when <test> <thens>)")
        (if (> (length thens) 1)
            `(begin ,@thens)
            (car thens)))))

(define (unless? e) (eq? 'unless (car e)))
(define (unless/test e) (cadr e))
(define (unless/elses e)
    (let ((elses (cddr e)))
    (if (null? elses)
        (error "empty <elses> in (unless <test> <elses>)")
        (if (> (length elses) 1)
            `(begin ,@elses)
            (car elses)))))

(define (begin? e) (eq? 'begin (car e)))
(define (begin/expressions e) (cdr e))

(define (cond? e) (eq? 'cond (car e)))
(define (cond/clauses e) (cdr e))

(define (lambda? e) (eq? 'lambda (car e)))
(define (lambda/parameters e) (cadr e))
(define (lambda/body e) (cddr e))

(define (and? e) (eq? 'and (car e)))
(define (or? e) (eq? 'or (car e)))

(define (call/operator e) (car e))
(define (call/arguments e) (cdr e))

;; (let <bindings> <body>) or
;; (let <variable> <bindings> <body>).
(define (let? e) (eq? 'let (car e)))
(define (let/bindings e) (cadr e))
(define (let/named/bindings e) (caddr e))
(define (let/named/body e) (cdddr e))
(define (let/body e) (cddr e))
(define (let/binding/symbol binding) (car binding))
(define (let/binding/expression binding) (cadr binding))

(define (let/bindings/variables bindings)
  (map (lambda (binding) (let/binding/symbol binding)) bindings))

(define (let/bindings/expressions bindings)
  (map (lambda (binding) (let/binding/expression binding)) bindings))

(define (quasiquote? e)
  (eq? 'quasiquote (car e)))

(define (unquote? e)
  (eq? 'unquote (car e)))

(define (unquote-splicing? e)
  (eq? 'unquote-splicing (car e)))

;; Internal set!
(define setter/tag
  (let ((tag (gensym 'setter/)))
    (lambda () tag)))  ; Production.
    ;(lambda () 'set!))) ; Debugging

(define (setter? e) (eq? (setter/tag) (car e)))
(define (setter/target e) (cadr e))
(define (setter/value e)  (caddr e))

;; Weird letrec/set tag.
;(define letrec/setter/tag
;  (let ((tag (gensym 'letrec/setter/)))
;    (lambda () tag)))
;
;(define (letrec/setter? e)
;  (eq? (letrec/setter/tag) (car e)))
;
;(define (letrec/setter/target e) (cadr e))
;(define (letrec/setter/value e)  (caddr e))

(define (variable? x)
  (if (symbol? x) #t (error (format "Identifier expected: ~a" x))))

(define (definition/macro? e) (eq? 'define-macro (car e)))

;; Returns #t if the given form is a list containing at least n >= 0 elements.
(define (shape form n)
  (let loop ((form form) (n n) (l form))
    (cond
      ((<= n 0))
      ((pair? l)
       (loop form (- n 1) (cdr l)))
      (else
       (error "Ill-constructed form" form)))))