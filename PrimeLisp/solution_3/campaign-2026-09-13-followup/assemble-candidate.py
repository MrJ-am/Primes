#!/usr/bin/env python3
"""One-time consolidation: keep the interface and only the selected kernels."""
import argparse
from pathlib import Path
p=Path(__file__).resolve().parent
parser=argparse.ArgumentParser()
parser.add_argument('--threshold',type=int,choices=[63,129],default=129)
parser.add_argument('--output',type=Path,default=p.parent/'sieve.lisp')
a=parser.parse_args()
b=(p/'baseline.lisp').read_text()
s=b[:b.index(';; The generated LOGIOR')]
s=s.replace('echologie-cl-hybrid129-unboxed',f'echologie-cl-kernels{a.threshold}')
s=s.replace('(debug 1)', '(debug 0)')
s+=';; Local byte update for the bounded sparse tail.\n'
s+=b[b.index('(defun or-byte!'):b.index(';; Sparse factors')]
for f in ['01-sparse-kernel.lisp','02-dense-kernel.lisp']:
    delta=(p/'variants'/f).read_text()
    delta=delta[delta.index('(eval-when'):delta.rindex('(setf *name*')]
    s+='\n'+delta
s+='''
;; Dispatch is generated for all odd factors, never a precomputed prime list.
(defmacro define-dispatchers ()
  `(progn
     (defun dense-reset (bits factor)
       (declare (type words bits) (type fixnum factor))
       (case factor ,@(loop for p from 3 to THRESHOLD by 2 collect
         `(,p (,(intern (format nil "DENSE-~D" p)) bits)))))
     (defun sparse-reset (bits factor)
       (declare (type words bits) (type fixnum factor))
       (let ((nbytes (ash (length bits) 3)))
         (declare (type fixnum nbytes))
         (case (logand factor 15)
           ,@(loop for r from 1 to 15 by 2 collect
             `(,r (,(intern (format nil "SPARSE-~D" r)) bits nbytes factor))))))))
(define-dispatchers)
'''.replace('THRESHOLD',str(a.threshold))
s+='\n'+b[b.index('(defun run-sieve'):].replace('(<= factor 129)',f'(<= factor {a.threshold})')
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(s)
print(a.output)
