;;;; SPDX-License-Identifier: BSD-3-Clause
;;;; SBCL x86-64: one bit per odd candidate, held in native 64-bit words.
;;;; Dense/sparse unrolling follows Mike Barber and GordonBGood's approach
;;;; in PrimeRust/solution_1; see EXPERIMENT.md for provenance and measurements.
;;;; No prime list or sieve result is precomputed: every call makes fresh state.
(defpackage #:prime-candidate
  (:use #:cl)
  (:export #:make-sieve #:run-sieve #:primep #:count-primes #:*tags* #:*name*))
(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(defparameter *name* "echologie-cl-hybrid129-unboxed")
(defparameter *tags* "algorithm=base,faithful=yes,bits=1")
(deftype words () '(simple-array (unsigned-byte 64) (*)))
(defclass word-sieve ()
  ((limit :initarg :limit :reader sieve-limit :type fixnum)
   (bits :initarg :bits :reader sieve-bits :type words)))
(defun make-sieve (limit)
  "Allocate a fresh object and runtime-sized odd-candidate array."
  (check-type limit (integer 0 #.most-positive-fixnum))
  (let ((bits (make-array (ceiling (ceiling limit 2) 64)
                          :element-type '(unsigned-byte 64) :initial-element 0)))
    (declare (type words bits))
    (when (plusp (length bits)) (setf (aref bits 0) 1))
    (make-instance 'word-sieve :limit limit :bits bits)))
(declaim (inline marked-p))
(defun marked-p (bits index)
  (declare (type words bits) (type fixnum index))
  (logbitp (logand index 63) (aref bits (ash index -6))))

;; The generated LOGIOR arguments are individual multiples of one factor.
;; SBCL folds their constant masks within a word. Every odd factor still has
;; a function: the running sieve, not a precomputed prime list, selects it.
(defmacro define-dense-resetters (maximum)
  (declare (optimize (speed 1)))
  `(progn
     ,@(loop for p from 3 to maximum by 2
             for name = (intern (format nil "DENSE-~D" p))
             for start = (* (floor (floor (* p p) 2) (* 64 p)) p)
             for updates =
               (loop for w below p
                     for masks = (loop for k below 64
                                       for bit = (+ (floor p 2) (* k p))
                                       when (= w (floor bit 64))
                                         collect (ash 1 (mod bit 64)))
                     when masks collect
                       `(let ((word (aref bits (+ base ,w))))
                          (declare (type (unsigned-byte 64) word))
                          (setf word (logior word ,@masks))
                          (setf (aref bits (+ base ,w)) word)))
             collect
               `(defun ,name (bits)
                  (declare (type words bits))
                  (let ((base ,start) (end (length bits)))
                    (declare (type fixnum base end))
                    (loop while (<= base (- end ,p)) do
                      ,@updates
                      (incf base ,p))
                    ,@(loop for update in updates
                            for w = (third (third (second (first (second update)))))
                            collect `(when (< (+ base ,w) end) ,update))
                    (setf (aref bits ,(floor (floor p 2) 64))
                          (logand (aref bits ,(floor (floor p 2) 64))
                                  ,(logxor #xffffffffffffffff (ash 1 (mod (floor p 2) 64)))))
                  nil)))
     (defun dense-reset (bits factor)
       (declare (type words bits) (type fixnum factor))
       (case factor
         ,@(loop for p from 3 to maximum by 2
                 collect `(,p (,(intern (format nil "DENSE-~D" p)) bits)))))))
(define-dense-resetters 129)

;; This local VOP emits one memory OR for a single composite flag. It does
;; not replace or modify SBCL's general bit-vector or arithmetic operations.
(defun or-byte! (sap offset mask)
  (declare (type sb-sys:system-area-pointer sap)
           (type (signed-byte 64) offset) (type (unsigned-byte 8) mask))
  (setf (sb-sys:sap-ref-8 sap offset)
        (logior (sb-sys:sap-ref-8 sap offset) mask))
  (values))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown or-byte! (sb-sys:system-area-pointer (signed-byte 64) (unsigned-byte 8))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (or-byte!)
    (:translate or-byte!)
    (:policy :fast-safe)
    (:args (sap :scs (sb-vm::sap-reg)) (offset :scs (sb-vm::signed-reg)))
    (:arg-types sb-vm::system-area-pointer sb-vm::signed-num (:constant (unsigned-byte 8)))
    (:info mask)
    (:generator 1
      (sb-assem:inst or :byte (sb-vm::ea 0 sap offset) mask))))

;; Sparse factors are >129, so the first chunk is past the factor's own bit.
;; Eight multiples repeat their bit positions; byte offsets remain dynamic.
;; On 64-bit SBCL, factors <= ISQRT(MOST-POSITIVE-FIXNUM) fit 31 bits;
;; byte offsets fit 31 bits and the full buffer plus a step fits 59 bits.
(defmacro define-sparse-resetters ()
  (declare (optimize (speed 1)))
  `(progn
     ,@(loop for equivalent from 1 to 15 by 2
             for name = (intern (format nil "SPARSE-~D" equivalent))
             for offsets = (loop for k below 8 collect (intern (format nil "OFFSET~D" k)))
             for masks = (loop for k below 8 collect
                              (ash 1 (mod (+ (floor equivalent 2) (* k equivalent)) 8)))
             for updates = (loop for offset in offsets for mask in masks collect
                                 `(or-byte! sap (the (signed-byte 64) (+ base ,offset)) ,mask))
             collect
             `(defun ,name (bits nbytes factor)
                (declare (type words bits) (type fixnum nbytes) (type (integer 3 #.(isqrt most-positive-fixnum)) factor)
                         (optimize (speed 3) (safety 0) (debug 1)))
                (sb-sys:with-pinned-objects (bits)
                  (let ((sap (sb-sys:vector-sap bits)))
                    (declare (type sb-sys:system-area-pointer sap))
                    (let ((base (* (floor (ash (* factor factor) -1) (ash factor 3)) factor))
                          ,@(loop for offset in offsets for k below 8 collect
                              `(,offset (ash (+ (ash factor -1) (* ,k factor)) -3))))
                  (declare (type (unsigned-byte 59) base) (type (unsigned-byte 31) ,@offsets))
                  (loop while (<= base (- nbytes factor)) do
                    ,@updates
                    (incf base factor))
                  ,@(loop for offset in offsets for update in updates collect
                          `(when (< (+ base ,offset) nbytes) ,update)))))
                nil))
     (defun sparse-reset (bits factor)
       (declare (type words bits) (type fixnum factor))
       (let ((nbytes (ash (length bits) 3)))
         (declare (type fixnum nbytes))
         (case (logand factor 15)
           ,@(loop for equivalent from 1 to 15 by 2 collect
                   `(,equivalent (,(intern (format nil "SPARSE-~D" equivalent)) bits nbytes factor))))))))
(define-sparse-resetters)

(defun run-sieve (sieve)
  (let ((bits (sieve-bits sieve)) (limit (sieve-limit sieve)))
    (declare (type words bits) (type fixnum limit))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          unless (marked-p bits (ash factor -1))
            do (if (<= factor 129) (dense-reset bits factor)
                   (sparse-reset bits factor))))
  sieve)
(defun primep (sieve number)
  (declare (type fixnum number))
  (and (<= 2 number (the fixnum (sieve-limit sieve)))
       (or (= number 2)
           (and (oddp number)
                (not (marked-p (sieve-bits sieve) (ash number -1)))))))
;; Ignore padding bits in the final machine word.
(defun count-primes (sieve)
  (let* ((limit (sieve-limit sieve)) (bits (sieve-bits sieve))
         (nbits (ceiling limit 2)) (nwords (ash nbits -6))
         (tail (logand nbits 63)))
    (declare (type words bits) (type fixnum limit nbits nwords tail))
    (+ (if (>= limit 2) 1 0)
       (- nbits
          (+ (loop for i fixnum below nwords sum (logcount (aref bits i)) fixnum)
             (if (zerop tail) 0
                 (logcount (logand (aref bits nwords) (1- (ash 1 tail))))))))))
