;;;; SPDX-License-Identifier: BSD-3-Clause
(eval-when (:compile-toplevel :load-toplevel :execute) (require :sb-simd))
(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 0)))
(defmacro define-simd-dense (maximum)
  `(progn
     ,@(loop for p from 3 to maximum by 2 collect
             (let ((masks (make-array p :element-type '(unsigned-byte 64) :initial-element 0)))
               (dotimes (k 64)
                 (let* ((bit (+ (floor p 2) (* k p))) (w (floor bit 64)))
                   (setf (aref masks w) (logior (aref masks w) (ash 1 (mod bit 64))))))
               `(defun ,(intern (format nil "DENSE-~D" p)) (bits)
                  (declare (type words bits))
                  (let ((end (length bits)) (base 0)
                        ,@(loop for i below p collect
                                `(,(intern (format nil "MASK-~D" i))
                                  (sb-simd-avx2:make-u64.4
                                   ,@(loop for lane below 4 collect (aref masks (mod (+ (* i 4) lane) p)))))))
                    (declare (type fixnum end base))
                    (loop while (<= (+ base ,(* p 4)) end) do
                      ,@(loop for i below p collect
                              `(setf (sb-simd-avx:u64.4-aref bits (+ base ,(* i 4)))
                                     (sb-simd-avx2:u64.4-or
                                      (sb-simd-avx:u64.4-aref bits (+ base ,(* i 4)))
                                      ,(intern (format nil "MASK-~D" i)))))
                      (incf base ,(* p 4)))
                    (loop for i fixnum from base below end do
                      (setf (aref bits i) (logior (aref bits i) (aref ,masks (mod i ,p)))))
                    (setf (aref bits 0) (logandc2 (aref bits 0) ,(ash 1 (floor p 2)))))
                  nil)))))
(define-simd-dense 7)
(setf *name* "echologie-cl-simd7-kernels")
