;;;; Independent final validation, loaded after the candidate and common harness.
;;;; This file is not shown to either developer during optimization.
(defpackage #:campaign-check (:use #:cl))
(in-package #:campaign-check)
(declaim (optimize (speed 1) (safety 3) (debug 2)))

(defun oracle (limit)
  "Full integer byte sieve, independent of the candidate's odd-bit word layout."
  (let ((flags (make-array (1+ limit) :element-type '(unsigned-byte 8)
                          :initial-element 1)))
    (setf (aref flags 0) 0)
    (when (>= limit 1) (setf (aref flags 1) 0))
    (loop for p from 2 to (isqrt limit)
          when (= 1 (aref flags p))
            do (loop for composite from (* p p) to limit by p
                     do (setf (aref flags composite) 0)))
    flags))

(defun trial-prime-p (n)
  (and (>= n 2) (loop for d from 2 to (isqrt n) never (zerop (mod n d)))))

(defun verify-limit (limit)
  (let* ((expected (oracle limit))
         (sieve (prime-candidate:make-sieve limit))
         (state (prime-candidate:run-sieve sieve)))
    (assert (or (typep sieve 'standard-object) (typep sieve 'structure-object))
            () "Fresh sieve state must be an instance of a class.")
    (assert (= (count 1 expected) (prime-candidate:count-primes state))
            () "Wrong count at limit ~D" limit)
    (loop for n from 0 to limit
          do (assert (eq (= 1 (aref expected n))
                         (not (null (prime-candidate:primep state n))))
                     () "Wrong flag at limit ~D, n=~D" limit n))
    (assert (not (prime-candidate:primep state (1+ limit))))
    ;; Creating a new instance must not clear or resize an older sieve.
    (let ((another (prime-candidate:make-sieve limit)))
      (assert (not (eq sieve another)))
      (assert (= (count 1 expected) (prime-candidate:count-primes state))))
    (prime-candidate:run-sieve (prime-candidate:make-sieve 17))
    (assert (= (count 1 expected) (prime-candidate:count-primes state)))
    (loop for n from 0 to limit
          do (assert (eq (= 1 (aref expected n))
                         (not (null (prime-candidate:primep state n))))))
    (format t "verified limit=~D primes=~D~%" limit (count 1 expected))))

(let ((small (oracle 2048)))
  (loop for n from 0 to 2048
        do (assert (eq (= 1 (aref small n)) (trial-prime-p n)))))

(dolist (limit '(0 1 2 3 4 9 25 49 63 64 65 127 128 129 255 256 257
                511 512 513 961 1023 1024 1025 3969 4095 4096 4097
                16129 16383 16384 16385 65025 65535 65536 65537
                99991 100000 999983 999999 1000000 1000001
                1042441 1048575 1048576 1048577 2000003))
  (verify-limit limit))

(format t "Independent full-flag and state-isolation validation passed.~%")
