#lang typed/racket

(require "util.rkt")

(provide (except-out (all-defined-out)
                     DPacket
                     DPacket-seqNo
                     DPacket-msgNo
                     DPacket-inOrder?
                     DPacket-body))

(struct: Packet ([stamp : Natural]
                 [destID : Natural]) #:transparent)

; line 3 of the header packet
(: timestamp-bytes (Packet -> Bytes))
(define (timestamp-bytes p) (make32 (Packet-stamp p)))

(: write-timestamp-bytes! (Packet Bytes -> Bytes))
(define (write-timestamp-bytes! p buffer) (write32! (Packet-stamp p) buffer 8))

; line 4 of the header packet
(: destid-bytes (Packet -> Bytes))
(define (destid-bytes p) (make32 (Packet-destID p)))

(: write-destid-bytes! (Packet Bytes -> Bytes))
(define (write-destid-bytes! p buffer) (write32! (Packet-destID p) buffer 12))

;; the `timestamp' field in the UDT header
(: timestamp (Bytes -> Natural))
(define (timestamp b) (take32 b 8))

;; the `destination socket ID' field in the UDT header
(: destid (Bytes -> Natural))
(define (destid b) (take32 b 12))

;; all packets must be at least 128 bits long
(: lacks-full-header? (Bytes -> Boolean))
(define (lacks-full-header? b) (< (bytes-length b) 16))

;;; ------------
;;; DATA PACKETS
;;; ------------


(struct: DPacket Packet ([seqNo : Natural] ; 31 bits
                         [msgNo : Natural] ; 29 bits
                         [inOrder? : Boolean]
                         [body : Bytes]) #:transparent)

;; these are separate types so they can share the implementation of DPacket (e.g., accessors)
(struct: FstPacket DPacket () #:transparent)
(struct: MidPacket DPacket () #:transparent)
(struct: LstPacket DPacket () #:transparent)
(struct: SinglePacket DPacket () #:transparent)

;; ... then this is used to constrain the actual allowed types of data packets
;; (i.e., no one can construct a DPacket which does not carry its positionality as a type)
(define-type DataPacket (U FstPacket MidPacket LstPacket SinglePacket))
(define DataPacket-body DPacket-body)
(define DataPacket-seqNo DPacket-seqNo)
(define DataPacket-msgNo DPacket-msgNo)
(define DataPacket-inOrder? DPacket-inOrder?)
(define-predicate DataPacket? DataPacket)

(define make-FstPacket FstPacket)
(define make-MidPacket MidPacket)
(define make-LstPacket LstPacket)
(define make-SinglePacket SinglePacket)

;;; ---------------
;;; CONTROL PACKETS
;;; ---------------
(define-type SocketType (U 'Stream 'Dgram))

(: SType->Nat (SocketType -> Natural))
(define (SType->Nat s)
  (cond [(equal? s 'Stream) 0]
        [(equal? s 'Dgram) 1]))

(: Nat->SType (Natural -> SocketType))
(define (Nat->SType i)
  (cond [(equal? i 0) 'Stream]
        [(equal? i 1) 'Dgram]
        [else (raise-parse-error (format "Invalid value for socket type: ~a" i))]))

(define-type ConnectionType (U 'Deny 'Accept 'CSReq 'RDVReq))

(: CType->Nat (ConnectionType -> Natural))
(define (CType->Nat c)
  (cond [(equal? c 'Deny) 0]
        [(equal? c 'Accept) 1]
        [(equal? c 'CSReq) 2]
        [(equal? c 'RDVReq) 3]))

(: Nat->CType (Natural -> ConnectionType))
(define (Nat->CType i)
  (cond [(equal? i 0) 'Deny]
        [(equal? i 1) 'Accept]
        [(equal? i 2) 'CSReq]
        [(equal? i 3) 'RDVReq]
        [else (raise-parse-error (format "Invalid value for connection type: ~a" i))]))

(struct: Shutdown Packet () #:transparent)

(struct: KeepAlive Packet () #:transparent)

(struct: Handshake Packet ([udtVersion : Natural]
                           [socketType : SocketType]
                           [initSeqNo : Natural]
                           [maxPacketSize : Natural]
                           [maxFlowWindowSize : Natural]
                           [connectionType : ConnectionType]
                           [channelID : Natural]
                           [SYNcookie : Natural]) #:transparent)
#|[peerIP : Natural] 
XXX fixme skipping for now, 
like Java impl) #:transparent) |#

(struct: DropReq Packet ([messageID : Natural]
                         [firstSeqNo : Natural]
                         [lastSeqNo : Natural]) #:transparent)

(struct: ACK2 Packet ([ACKNo : Natural]) #:transparent)

(struct: NAK Packet ([lossInfo : (Listof Natural)]) #:transparent)

(struct: LightACK Packet ([ACKNo : Natural]
                          [lastSeqNo : Natural]) #:transparent)

(struct: MedACK Packet ([ACKNo : Natural]
                        [lastSeqNo : Natural]
                        [RTT : Natural]
                        [RTTVariance : Natural]) #:transparent)

(struct: FullACK Packet ([ACKNo : Natural]
                         [lastSeqNo : Natural]
                         [RTT : Natural]
                         [RTTVariance : Natural]
                         [availBuffBytes : Natural]
                         [receiveRate : Natural]
                         [linkCap : Natural]) #:transparent)

(define-type ACK (U LightACK MedACK FullACK))
(define-predicate ACK? ACK)

(define make-Handshake Handshake)
(define make-Shutdown Shutdown)
(define make-KeepAlive KeepAlive)
(define make-LightACK LightACK)
(define make-MedACK MedACK)
(define make-FullACK FullACK)
(define make-NAK NAK)
(define make-ACK2 ACK2)
(define make-DropReq DropReq)

(define-type ControlPacket (U Handshake KeepAlive ACK ACK2 NAK Shutdown DropReq))
(define-predicate ControlPacket? ControlPacket)

;; XXX Fixme implement user defined control packet