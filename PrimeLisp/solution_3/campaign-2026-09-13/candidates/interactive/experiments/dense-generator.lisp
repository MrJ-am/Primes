(in-package #:prime-candidate)
(defmacro define-dense-resetters (maximum)
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
                          ,@(loop for mask in masks collect
                                  `(setf word (logior word ,mask)))
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
