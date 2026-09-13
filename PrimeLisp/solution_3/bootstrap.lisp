;;;; Invoked from the solution directory by run.sh, in a fresh SBCL image.
(dolist (name '("sieve" "bench"))
  (let ((output (format nil ".build/~A.fasl" name)))
    (ensure-directories-exist output)
    (multiple-value-bind (fasl warnings failure)
        (compile-file (format nil "~A.lisp" name) :output-file output
                      :verbose nil :print nil)
      (declare (ignore warnings))
      (when failure (error "Compilation failed for ~A." name))
      (load fasl))))
