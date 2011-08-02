#lang racket/base

(require "../../Motile/struct.rkt")
(provide (all-defined-out))

(define-motile-struct AddCURL [curl])
(define-motile-struct RemoveCURL [curl])
(define-motile-struct Quit [])
(define-motile-struct None [])
(define-motile-struct Frame [data timestamp])
(define-motile-struct FrameBuffer [data size disposal ts])
(define-motile-struct VideoParams [width height fpsNum fpsDen])

(define (dispose-FrameBuffer f)
  ((FrameBuffer.disposal f)))

(define (FrameBuffer->Frame v)
  (Frame (subbytes (FrameBuffer.data v) 0 (FrameBuffer.size v)) (FrameBuffer.ts v)))

#|(define b (AddCURL 'foo))
b
(AddCURL? b)
(AddCURL.curl b)
(AddCURL? (AddCURL!curl b 'bar))|#