(in-package "SB-X86-64-ASM")
(format t "~%Relevant optimizer symbols:~%")
(dolist (name '("DEFPATTERN" "PARSE-2-OPERANDS" "STMT-OPERANDS"
                "ENCODE-SIZE-PREFIX" "ASMSTREAM-CONSTANT-VECTOR"
                "ADD-STMT-LABELS" "DELETE-STMT" "DEFTRANSFORM"))
  (let ((s (find-symbol name)))
    (format t "~A ~A ~A~%" name s (and s (fboundp s)))))
(let ((fn (find-symbol "DEFPATTERN")))
  (when fn (pprint (macroexpand-1 `(,fn "probe OR OR" ((or) (or)) (stmt next) nil)))))
