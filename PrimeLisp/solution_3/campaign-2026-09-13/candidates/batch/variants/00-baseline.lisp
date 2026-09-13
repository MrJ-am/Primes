;;;; Shared, deliberately simple starting point for both development methods.

(defpackage #:prime-candidate
  (:use #:cl)
  (:export #:make-sieve #:run-sieve #:primep #:count-primes #:*tags* #:*name*))
(in-package #:prime-candidate)

(declaim (optimize (speed 3) (safety 1) (debug 1)))

(defparameter *name* "echologie-cl-baseline")
(defparameter *tags* "algorithm=base,faithful=yes,bits=1")

(defclass sieve-state ()
  ((limit :initarg :limit :reader sieve-limit :type fixnum)
   (bits :initarg :bits :reader sieve-bits :type simple-bit-vector)))

(defun make-sieve (limit)
  "Allocate a fresh sieve for the integers from 0 through LIMIT inclusive."
  (check-type limit (integer 0 #.most-positive-fixnum))
  (let ((bits (make-array (ceiling limit 2) :element-type 'bit
                         :initial-element 0)))
    ;; Bit i represents 2i+1; 1 is not prime. Even numbers are implicit.
    (when (plusp (length bits)) (setf (sbit bits 0) 1))
    (make-instance 'sieve-state :limit limit :bits bits)))

(defun run-sieve (sieve)
  (let ((bits (sieve-bits sieve))
        (limit (sieve-limit sieve)))
    (declare (type simple-bit-vector bits) (type fixnum limit))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          when (zerop (sbit bits (ash factor -1)))
            do (loop for index fixnum from (ash (* factor factor) -1)
                     below (length bits) by factor
                     do (setf (sbit bits index) 1))))
  sieve)

(defun primep (sieve number)
  (declare (type fixnum number))
  (and (<= 2 number (the fixnum (sieve-limit sieve)))
       (or (= number 2)
           (and (oddp number)
                (zerop (sbit (sieve-bits sieve) (ash number -1)))))))

(defun count-primes (sieve)
  (+ (if (>= (the fixnum (sieve-limit sieve)) 2) 1 0)
     (count 0 (sieve-bits sieve))))
