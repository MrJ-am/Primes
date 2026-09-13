;;; Code-generation analogue of the dense resetters in Mike Barber's and
;;; GordonBGood's Rust hybrid: every source operation marks one composite bit.
;;; The compiler may combine adjacent constant OR operations in one word.
(defmacro define-dense-resetters (maximum)
  `(progn
     ,@(loop for factor from 3 to maximum by 2
             for name = (intern (format nil "DENSE-~D" factor))
             for first-word = (* factor (floor (floor (* factor factor) 2)
                                                 (* 64 factor)))
             collect
             (let ((groups (make-array factor :initial-element nil)))
               (dotimes (i 64)
                 (let ((index (+ (floor factor 2) (* i factor))))
                   (push (ash 1 (mod index 64)) (aref groups (floor index 64)))))
               (flet ((word-form (offset masks)
                        `(let ((word (aref words (+ base ,offset))))
                           (declare (type (unsigned-byte 64) word))
                           ,@(loop for mask in (reverse masks)
                                   collect `(setf word (logior word ,mask)))
                           (setf (aref words (+ base ,offset)) word))))
                 `(defun ,name (words)
                    (declare (type words words))
                    (let ((base ,first-word) (end (length words)))
                      (declare (type fixnum base end))
                      (loop while (<= (+ base ,factor) end)
                            do ,@(loop for masks across groups for i from 0
                                       when masks collect (word-form i masks))
                               (incf base ,factor))
                      ,@(loop for masks across groups for i from 0 when masks
                              collect `(when (< (+ base ,i) end)
                                         ,(word-form i masks)))
                      ;; Dense alignment can include the factor itself.
                      (setf (aref words ,(floor (floor factor 2) 64))
                            (logandc2 (aref words ,(floor (floor factor 2) 64))
                                      ,(ash 1 (mod (floor factor 2) 64)))))
                    (values)))))))
(define-dense-resetters 129)
(defmacro dense-dispatch (factor words fallback)
  `(case ,factor
     ,@(loop for p from 3 to 129 by 2
             collect `(,p (,(intern (format nil "DENSE-~D" p)) ,words)))
     (otherwise ,fallback)))
