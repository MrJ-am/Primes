(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(defmacro define-sparse-resetters ()
  (declare (optimize (speed 1)))
  `(progn
     ,@(loop for equivalent from 1 to 15 by 2
             for name = (intern (format nil "SPARSE-~D" equivalent))
             for carries = (loop for k below 8 collect
                                 (floor (+ (floor equivalent 2) (* k (mod equivalent 8))) 8))
             for masks = (loop for k below 8 collect
                              (ash 1 (mod (+ (floor equivalent 2) (* k equivalent)) 8)))
             for addressing = '((q 1) (q 1) (q 2) (q3 1) (q 4) (q5 1) (q3 2) (q7 1))
             for updates = (loop for k below 8 for carry in carries for mask in masks
                                 for (index scale) in addressing collect
                                 (if (zerop k) `(or-byte-constant! ptr ,carry ,mask)
                                     `(or-byte-scaled! ptr ,index ,scale ,carry ,mask)))
             collect
             `(defun ,name (sap nbytes factor)
                (declare (type sb-sys:system-area-pointer sap)
                         (type fixnum nbytes)
                         (type (integer 3 #.(isqrt most-positive-fixnum)) factor)
                         (optimize (speed 3) (safety 0) (debug 1)))
                (let* ((q (ash factor -3)) (q3 (* q 3)) (q5 (* q 5)) (q7 (* q 7))
                       (first (ash factor -4)) (start (* first factor))
                       (blocks (floor (- nbytes start) factor))
                       (tail (- nbytes start (* blocks factor) first))
                       (step factor)
                       (ptr (sb-sys:sap+ sap (+ start first))))
                  (declare (type (signed-byte 64) q q3 q5 q7 step)
                           (type fixnum first start blocks tail)
                           (type sb-sys:system-area-pointer ptr))
                  (loop repeat blocks do
                    ,@updates
                    (setf ptr (sb-sys:sap+ ptr step)))
                  ,@(loop for k below 8 for carry in carries for update in updates collect
                          `(when (< (the fixnum (+ (* ,k q) ,carry)) tail) ,update)))
                nil))
     (defun sparse-reset (bits factor)
       (declare (type words bits) (type fixnum factor))
       (sb-sys:with-pinned-objects (bits)
         (let ((sap (sb-sys:vector-sap bits)) (nbytes (ash (length bits) 3)))
           (declare (type sb-sys:system-area-pointer sap) (type fixnum nbytes))
           (case (logand factor 15)
             ,@(loop for equivalent from 1 to 15 by 2 collect
                     `(,equivalent (,(intern (format nil "SPARSE-~D" equivalent)) sap nbytes factor)))))))))
(define-sparse-resetters)
