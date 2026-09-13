;;; Eight single-bit masks per block, specialized by the factor modulo 16.
;;; The words remain the owning storage; SAP access only views their bytes.
(defmacro define-sparse-resetters ()
  `(progn
     ,@(loop for residue from 1 to 15 by 2
             for name = (intern (format nil "SPARSE-~D" residue))
             collect
             (let ((indices (loop repeat 8 collect (gensym "INDEX"))))
               `(defun ,name (words factor)
                  (declare (type words words) (type fixnum factor))
                  (let* ((half (ash factor -1))
                         (base (* factor (floor (ash (* factor factor) -1)
                                                (* factor 8))))
                         (end (* 8 (length words)))
                         ,@(loop for index in indices for i from 0
                                 collect `(,index (ash (+ half (* ,i factor)) -3))))
                    (declare (type fixnum half base end ,@indices))
                    (sb-sys:with-pinned-objects (words)
                      (let ((sap (sb-sys:vector-sap words)))
                        (declare (type sb-sys:system-area-pointer sap))
                        (loop while (<= (+ base factor) end)
                              do ,@(loop for index in indices for i from 0
                                         for mask = (ash 1 (mod (+ (floor residue 2)
                                                                  (* i residue)) 8))
                                         collect
                                         `(setf (sb-sys:sap-ref-8 sap (+ base ,index))
                                                (logior (sb-sys:sap-ref-8 sap (+ base ,index))
                                                        ,mask)))
                                 (incf base factor))
                        ,@(loop for index in indices for i from 0
                                for mask = (ash 1 (mod (+ (floor residue 2) (* i residue)) 8))
                                collect
                                `(when (< (+ base ,index) end)
                                   (setf (sb-sys:sap-ref-8 sap (+ base ,index))
                                         (logior (sb-sys:sap-ref-8 sap (+ base ,index))
                                                 ,mask)))))))
                  (values))))))
(define-sparse-resetters)
(defmacro sparse-dispatch (factor words)
  `(case (logand ,factor 15)
     ,@(loop for residue from 1 to 15 by 2
             collect `(,residue (,(intern (format nil "SPARSE-~D" residue))
                                ,words ,factor)))))
