;;;; SPDX-License-Identifier: BSD-3-Clause
;;;; SBCL 2.6.8, Linux x86-64. One bit per odd candidate.
;;;; Native allocation/free, single-bit marking, and unrolled dense/sparse loops.
;;;; Dense/sparse patterns follow Mike Barber and GordonBGood (PrimeRust/solution_1).
;;;; No prime list or sieve result is precomputed. See README.md for the algorithm and development approach.
(defpackage #:prime-memory
  (:use #:cl) (:nicknames #:pm)
  (:export #:with-sieve #:run-sieve #:primep #:count-primes #:*name* #:*tags*))
(in-package #:prime-memory)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))
(defparameter *name* "cl-base")
(defparameter *tags* "algorithm=base,faithful=yes,bits=1")
(defun checked-limit (limit)
  (declare (optimize (safety 3)))
  (check-type limit (integer 0 #.most-positive-fixnum))
  limit)
(defun mark-flags! (storage offset mask)
  (declare (type sb-sys:system-area-pointer storage)
           (type (signed-byte 64) offset) (type (unsigned-byte 8) mask))
  (setf (sb-sys:sap-ref-8 storage offset)
        (logior (sb-sys:sap-ref-8 storage offset) mask))
  (values))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown mark-flags! (sb-sys:system-area-pointer (signed-byte 64) (unsigned-byte 8))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (mark-flags!)
    (:translate mark-flags!)
    (:policy :fast-safe)
    (:args (storage :scs (sb-vm::sap-reg)) (offset :scs (sb-vm::signed-reg)))
    (:arg-types sb-vm::system-area-pointer sb-vm::signed-num (:constant (unsigned-byte 8)))
    (:info mask)
    (:generator 1
      (sb-assem:inst or :byte (sb-vm::ea 0 storage offset) mask))))


;; Mark complete groups of eight multiples; the caller handles the partial tail.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown mark-multiple-groups!
      (sb-sys:system-area-pointer (unsigned-byte 64) (unsigned-byte 64)
       (unsigned-byte 64) (integer 1 15))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (mark-multiple-groups!)
    (:translate mark-multiple-groups!) (:policy :fast-safe)
    ;; Keep inputs live until all temporary-register computations finish.
    (:args (storage :scs (sb-vm::sap-reg) :to :save)
           (group-count :scs (sb-vm::unsigned-reg) :to :save)
           (byte-stride :scs (sb-vm::unsigned-reg) :to :save)
           (step :scs (sb-vm::unsigned-reg) :to :save))
    (:arg-types sb-vm::system-area-pointer sb-vm::unsigned-num sb-vm::unsigned-num sb-vm::unsigned-num (:constant (integer 1 15)))
    (:info residue)
    (:temporary (:sc sb-vm::sap-reg) cursor)
    (:temporary (:sc sb-vm::unsigned-reg) remaining stride-3 stride-5 stride-7)
    (:generator 1
      (let ((again (sb-assem:gen-label)) (done (sb-assem:gen-label)))
        (sb-vm::move cursor storage)
        (sb-vm::move remaining group-count)
        (sb-assem:inst test remaining remaining)
        (sb-assem:inst jmp :z done)
        (sb-assem:inst lea stride-3 (sb-vm::ea 0 byte-stride byte-stride 2))
        (sb-assem:inst lea stride-5 (sb-vm::ea 0 byte-stride byte-stride 4))
        (sb-assem:inst lea stride-7 (sb-vm::ea 0 stride-3 byte-stride 4))
        (sb-assem:emit-label again)
        (loop for k below 8 for index in (list nil byte-stride byte-stride stride-3 byte-stride stride-5 stride-3 stride-7)
              for scale in '(1 1 2 1 4 1 2 1)
              for carry = (floor (+ (floor residue 2) (* k (mod residue 8))) 8)
              for mask = (ash 1 (mod (+ (floor residue 2) (* k residue)) 8))
              do (sb-assem:inst or :byte (sb-vm::ea carry cursor index scale) mask))
        (sb-assem:inst add cursor step)
        (sb-assem:inst dec remaining)
        (sb-assem:inst jmp :nz again)
        (sb-assem:emit-label done)))))

(sb-alien:define-alien-routine ("malloc" allocate-storage) sb-alien:unsigned-long
  (size sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("free" release-storage) sb-alien:void
  (address sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("memset" fill-storage) sb-alien:unsigned-long
  (address sb-alien:unsigned-long) (value sb-alien:int) (size sb-alien:unsigned-long))
(declaim (inline make-sieve-state))
(defstruct sieve-state
  (limit 0 :type fixnum) (word-count 0 :type fixnum)
  (address 0 :type (unsigned-byte 64)))
(defmacro with-sieve-state ((state limit) &body body)
  (let ((n (gensym)) (word-count (gensym)) (address (gensym)))
    `(let* ((,n (checked-limit ,limit)) (,word-count (ceiling (ceiling ,n 2) 64))
            (,address (allocate-storage (max 8 (* ,word-count 8)))))
       (declare (type fixnum ,n ,word-count) (type (unsigned-byte 64) ,address))
       (when (zerop ,address) (error "Native allocation failed."))
       (unwind-protect
            (let ((,state (make-sieve-state :limit ,n :word-count ,word-count :address ,address)))
              (declare (dynamic-extent ,state))
              (fill-storage ,address 0 (* ,word-count 8))
              (when (plusp ,word-count) (setf (sb-sys:sap-ref-64 (sb-sys:int-sap ,address) 0) 1))
              ,@body)
         (release-storage ,address)))))
(declaim (inline composite-flag-p))
(defun composite-flag-p (address index)
  (declare (type (unsigned-byte 64) address) (type fixnum index))
  (logbitp (logand index 63)
           (sb-sys:sap-ref-64 (sb-sys:int-sap address) (ash (ash index -6) 3))))

;; Generate single-bit operations in increasing multiple order. Adjacent
;; operations on the same word keep a Lisp temporary, as in Lisp solution_2.
;; Constant folding belongs to SBCL; no multi-composite masks are constructed.
(defmacro define-dense-markers ()
  `(progn
     ,@(loop for p from 3 to 63 by 2 collect
       `(defun ,(intern (format nil "MARK-INITIAL-BY-~D" p)) (address word-count)
          (declare (type (unsigned-byte 64) address) (type fixnum word-count))
          (let* ((storage (sb-sys:int-sap address))
                 (cursor (sb-sys:sap+ storage ,(* 8 p (floor p 128))))
                 (i ,(* p (floor p 128))))
            (declare (type fixnum i))
            (loop while (<= (+ i ,p) word-count) do
              ,@(loop for word below p
                      for bits = (loop for k below 64
                                       for bit = (+ (floor p 2) (* k p))
                                       when (= word (floor bit 64)) collect (mod bit 64))
                      when bits collect
                        `(let* ((value (sb-sys:sap-ref-64 cursor ,(* word 8)))
                                ,@(loop for bit in bits collect
                                        `(value (logior value ,(ash 1 bit)))))
                           (setf (sb-sys:sap-ref-64 cursor ,(* word 8)) value)))
              (setf cursor (sb-sys:sap+ cursor ,(* p 8)))
              (incf i ,p))
            (loop for k fixnum below 64
                  for bit fixnum = (+ ,(floor p 2) (* k ,p))
                  for word fixnum = (+ i (ash bit -6))
                  while (< word word-count) do
              (setf (sb-sys:sap-ref-64 storage (ash word 3))
                    (logior (sb-sys:sap-ref-64 storage (ash word 3))
                            (ash 1 (logand bit 63)))))
            (setf (sb-sys:sap-ref-64 storage ,(* 8 (floor p 128)))
                  (logand (sb-sys:sap-ref-64 storage ,(* 8 (floor p 128)))
                          ,(logxor #xffffffffffffffff (ash 1 (mod (floor p 2) 64))))))
          nil))
     (defun mark-initial-small-factor (address word-count factor)
       (declare (type (unsigned-byte 64) address) (type fixnum word-count factor))
       (case factor
         ,@(loop for p from 3 to 63 by 2 collect
             `(,p (,(intern (format nil "MARK-INITIAL-BY-~D" p)) address word-count)))))))
(define-dense-markers)

(defmacro define-initial-markers ()
  `(progn
     ,@(loop for r from 1 to 15 by 2 collect
       `(defun ,(intern (format nil "MARK-INITIAL-RESIDUE-~D" r)) (address byte-count factor)
          (declare (type (unsigned-byte 64) address) (type fixnum byte-count)
                   (type (integer 3 2147483647) factor))
          (let* ((first (ash factor -4)) (start (* first factor)) (byte-stride (ash factor -3))
                 (group-count (floor (- byte-count start) factor))
                 (tail (+ start first (* group-count factor)))
                 (storage (sb-sys:int-sap address)))
            (declare (type (unsigned-byte 59) first start byte-stride group-count tail))
            (mark-multiple-groups! (sb-sys:sap+ storage (+ start first)) group-count byte-stride factor ,r)
            ,@(loop for k below 8
               for carry = (floor (+ (floor r 2) (* k (mod r 8))) 8)
               for mask = (ash 1 (mod (+ (floor r 2) (* k r)) 8))
               collect `(let ((index (+ tail (* ,k byte-stride) ,carry)))
                          (declare (type (unsigned-byte 59) index))
                          (when (< index byte-count) (mark-flags! storage index ,mask)))))
          nil))
     (defun mark-initial-large-factor (address byte-count factor)
       (declare (type (unsigned-byte 64) address) (type fixnum byte-count factor))
       (case (logand factor 15) ,@(loop for r from 1 to 15 by 2 collect
          `(,r (,(intern (format nil "MARK-INITIAL-RESIDUE-~D" r)) address byte-count factor)))))))
(define-initial-markers)

(defun mark-composites (state)
  (let ((address (sieve-state-address state)) (words (sieve-state-word-count state)))
    (loop for factor fixnum from 3 to (isqrt (sieve-state-limit state)) by 2
          unless (composite-flag-p address (ash factor -1)) do
            (if (<= factor 63)
                (mark-initial-small-factor address words factor)
                (mark-initial-large-factor address (ash words 3) factor))))
  state)

(defun sieve-prime-p (state number)
  (declare (type fixnum number))
  (and (<= 2 number (sieve-state-limit state))
       (or (= number 2) (and (oddp number)
         (not (composite-flag-p (sieve-state-address state) (ash number -1)))))))
(defun count-sieve-primes (state)
  (let* ((limit (sieve-state-limit state)) (storage (sb-sys:int-sap (sieve-state-address state)))
         (candidate-count (ceiling limit 2)) (word-count (ash candidate-count -6)) (tail (logand candidate-count 63)))
    (declare (type fixnum limit candidate-count word-count tail))
    (+ (if (>= limit 2) 1 0)
       (- candidate-count (+ (loop for i fixnum below word-count sum
                   (logcount (sb-sys:sap-ref-64 storage (ash i 3))) fixnum)
                  (if (zerop tail) 0
                    (logcount (logand (sb-sys:sap-ref-64 storage (ash word-count 3))
                                     (1- (ash 1 tail))))))))))


(defmacro with-sieve ((state limit) &body body)
  "Create fresh state; release native memory on normal and nonlocal exits.
STATE and its address must not escape BODY. No finalizer or GC is needed."
  `(with-sieve-state (,state ,limit) ,@body))
(declaim (inline run-sieve primep count-primes))
(defun run-sieve (state) (mark-composites state))
(defun primep (state number) (sieve-prime-p state number))
(defun count-primes (state) (count-sieve-primes state))
