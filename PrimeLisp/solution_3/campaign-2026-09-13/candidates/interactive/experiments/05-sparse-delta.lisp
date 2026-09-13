(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(defmacro define-sparse-resetters ()
  (declare (optimize (speed 1)))
  `(progn
     ,@(loop for equivalent from 1 to 15 by 2
             for name = (intern (format nil "SPARSE-~D" equivalent))
             for offsets = (loop for k below 8 collect (intern (format nil "OFFSET~D" k)))
             for masks = (loop for k below 8 collect
                              (ash 1 (mod (+ (floor equivalent 2) (* k equivalent)) 8)))
             for updates = (loop for offset in offsets for mask in masks collect
                                 `(setf (sb-sys:sap-ref-8 sap (+ base ,offset))
                                        (logior (sb-sys:sap-ref-8 sap (+ base ,offset)) ,mask)))
             collect
             `(defun ,name (sap nbytes factor)
                (declare (type sb-sys:system-area-pointer sap) (type fixnum nbytes factor)
                         (optimize (speed 3) (safety 0) (debug 1)))
                (let ((base (* (floor (ash (* factor factor) -1) (ash factor 3)) factor))
                      ,@(loop for offset in offsets for k below 8 collect
                              `(,offset (ash (+ (ash factor -1) (* ,k factor)) -3))))
                  (declare (type fixnum base ,@offsets))
                  (loop while (<= base (- nbytes factor)) do
                    ,@updates
                    (incf base factor))
                  ,@(loop for offset in offsets for update in updates collect
                          `(when (< (+ base ,offset) nbytes) ,update)))
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

(defun run-sieve (sieve)
  (let* ((bits (sieve-bits sieve)) (limit (sieve-limit sieve))
         (end (ceiling limit 2)))
    (declare (type words bits) (type fixnum limit end))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          unless (marked-p bits (ash factor -1))
            do (if (<= factor 129) (dense-reset bits factor)
                   (sparse-reset bits factor))))
  sieve)

(setf *name* "echologie-cl-hybrid129-speed3")
