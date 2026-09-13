(in-package #:prime-candidate)
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
                (declare (type sb-sys:system-area-pointer sap) (type fixnum nbytes factor))
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
