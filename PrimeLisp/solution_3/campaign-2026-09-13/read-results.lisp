;;;; Convert SBCL's readable result records into simple delimited rows.
;;;; Each argument is a trusted local log; no read-time evaluation is allowed.
(let ((*read-eval* nil))
  (dolist (file (cdr sb-ext:*posix-argv*))
    (with-open-file (input file)
      (let* ((record (read input))
             (method (getf record :method))
             (label (getf record :label)))
        (loop for sample in (getf record :samples)
              for index from 1
              do (format t "~{~A~^|~}~%"
                         (list file (getf record :utc-universal-time) method
                               (getf record :mode) label (getf record :sbcl)
                               (getf record :cpu) (getf record :tags) index
                               (getf sample :passes) (getf sample :seconds)
                               (getf sample :microseconds-per-sieve)
                               (getf sample :sieves-per-second)
                               (getf sample :cpu-seconds)
                               (getf sample :bytes-consed)
                               (getf sample :gc-seconds))))))))
