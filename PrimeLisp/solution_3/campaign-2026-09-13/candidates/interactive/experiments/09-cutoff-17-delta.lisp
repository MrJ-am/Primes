(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(defun run-sieve (sieve)
  (let* ((bits (sieve-bits sieve)) (limit (sieve-limit sieve))
         (end (ceiling limit 2)))
    (declare (type words bits) (type fixnum limit end))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          unless (marked-p bits (ash factor -1))
            do (if (<= factor 17) (dense-reset bits factor)
                   (sparse-reset bits factor))))
  sieve)

(setf *name* "echologie-cl-hybrid17-vop")
