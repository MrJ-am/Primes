;;;; Fresh, odd-only Eratosthenes sieve. BSD-3-Clause.
(defpackage #:prime-candidate
  (:use #:cl)
  (:export #:make-sieve #:run-sieve #:primep #:count-primes #:*tags* #:*name*))
(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 0)))
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))
(defparameter *name* "echologie-cl-batch-hybrid-block")
(defparameter *tags* "algorithm=base,faithful=yes,bits=1")
(deftype words () '(simple-array (unsigned-byte 64) (*)))
(defclass sieve-state ()
  ((limit :initarg :limit :reader sieve-limit :type fixnum)
   (bits :initarg :bits :reader sieve-bits :type words)))
(defun make-sieve (limit)
  "Allocate a fresh instance and its own runtime-sized bit storage."
  (check-type limit (integer 0 #.most-positive-fixnum))
  (let ((bits (make-array (ceiling limit 128) :element-type '(unsigned-byte 64)
                         :initial-element 0)))
    (when (plusp (length bits)) (setf (aref bits 0) 1))
    (make-instance 'sieve-state :limit limit :bits bits)))
(declaim (inline marked-p mark))
(defun marked-p (words index)
  (declare (type words words) (type fixnum index))
  (logbitp (logand index 63) (aref words (ash index -6))))
(defun mark (words index)
  (declare (type words words) (type fixnum index))
  (let ((word-index (ash index -6)))
    (setf (aref words word-index)
          (logior (aref words word-index)
                  (the (unsigned-byte 64) (ash 1 (logand index 63)))))))
;;; SBCL-specific generic peephole optimization, adapted from Robert Mayer's
;;; PrimeLisp/solution_2/PrimeSievebitops.lisp (repository contribution terms).
;;; Consecutive ORs on one register are associative, including the final flags.
;;; No sieve factors, masks, or precomputed sieve data appear in this pass.
(in-package "SB-X86-64-ASM")
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defpattern "batch: combine constant ORs" ((or) (or)) (stmt next)
    (binding* (((size1 dst1 src1) (parse-2-operands stmt))
               ((size2 dst2 src2) (parse-2-operands next)))
      (labels ((constant-value (operand)
                 (if (ea-p operand)
                     (let ((constants (asmstream-constant-vector *asmstream*)))
                       (loop for constant across constants
                             when (eq (ea-disp operand) (cdr constant))
                               return (cdar constant)))
                     operand)))
        (when (and (null (stmt-labels next)) (gpr-tn-p dst1) (location= dst2 dst1)
                   (eq size1 :qword) (eq size2 :qword)
                   (or (integerp src1) (ea-p src1))
                   (or (integerp src2) (ea-p src2)))
          (let ((value1 (constant-value src1))
                (value2 (constant-value src2)))
            (when (and (integerp value1) (integerp value2))
              (setf (stmt-operands next)
                    `(,(encode-size-prefix :qword) ,dst2
                       ,(sb-vm::constantize (logior value1 value2))))
              (add-stmt-labels next (stmt-labels stmt))
              (delete-stmt stmt)
              next)))))))
(in-package #:prime-candidate)
;;; Keep each source mark a single-bit OR; let the generic peephole combine it.
(eval-when (:compile-toplevel :load-toplevel :execute)
(sb-c:defknown %word-or ((unsigned-byte 64) (unsigned-byte 64))
    (unsigned-byte 64) (sb-c:foldable sb-c:flushable sb-c:movable) :overwrite-fndb-silently t)
)
(in-package "SB-VM")
(eval-when (:compile-toplevel :load-toplevel :execute)
(define-vop (prime-candidate::%word-or)
  (:translate prime-candidate::%word-or)
  (:policy :fast-safe)
  (:args (word :scs (unsigned-reg) :target result))
  (:arg-types unsigned-num (:constant (unsigned-byte 64)))
  (:results (result :scs (unsigned-reg)))
  (:result-types unsigned-num)
  (:info mask)
  (:generator 1
    (move result word)
    (inst or result (constantize mask))))
)
(in-package #:prime-candidate)

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
                                   collect `(setf word (%word-or word ,mask)))
                           (setf (aref words (+ base ,offset)) word))))
                 `(defun ,name (words)
                    (declare (type words words))
                    (let ((base ,first-word) (end (length words)))
                      (declare (type (integer 0 #.(- most-positive-fixnum 1024)) base end))
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

;;; Eight single-bit masks per block, specialized by the factor modulo 16.
;;; The words remain the owning storage; SAP access only views their bytes.
(in-package #:prime-candidate)
;;; A byte OR with an immediate single-bit mask, avoiding fixnum conversions.
;;; This VOP has no sieve-specific knowledge and changes exactly the bit given.
(eval-when (:compile-toplevel :load-toplevel :execute)
(sb-c:defknown %or-byte (sb-sys:system-area-pointer (unsigned-byte 64)
                       (unsigned-byte 8)) (values)
    (sb-c:always-translatable) :overwrite-fndb-silently t)
)
(in-package "SB-VM")
(eval-when (:compile-toplevel :load-toplevel :execute)
(define-vop (prime-candidate::%or-byte)
  (:translate prime-candidate::%or-byte)
  (:policy :fast-safe)
  (:args (sap :scs (sap-reg)) (index :scs (unsigned-reg)))
  (:arg-types system-area-pointer unsigned-num (:constant (unsigned-byte 8)))
  (:info mask)
  (:generator 1 (inst or :byte (ea 0 sap index) mask)))
)
(in-package #:prime-candidate)

(defmacro define-sparse-resetters ()
  `(progn
     ,@(loop for residue from 1 to 15 by 2
             for name = (intern (format nil "SPARSE-~D" residue))
             collect
             (let ((indices (loop repeat 8 collect (gensym "INDEX"))))
               `(defun ,name (words factor)
                  (declare (type words words) (type (integer 3 2147483647) factor))
                  (let* ((half (ash factor -1))
                         (base (* factor (ash factor -4)))
                         (end (* 8 (length words)))
                         ,@(loop for index in indices for i from 0
                                 collect `(,index (ash (+ half (* ,i factor)) -3))))
                    (declare (type (integer 0 #.(- most-positive-fixnum #x1000000000)) half base end ,@indices))
                    (sb-sys:with-pinned-objects (words)
                      (let ((sap (sb-sys:vector-sap words)))
                        (declare (type sb-sys:system-area-pointer sap))
                        (loop while (<= (+ base factor) end)
                              do (let ((block (sb-sys:sap+ sap base)))
                                   ,@(loop for index in indices for i from 0
                                         for mask = (ash 1 (mod (+ (floor residue 2)
                                                                  (* i residue)) 8))
                                         collect
                                         `(%or-byte block ,index ,mask)))
                                 (incf base factor))
                        ,@(loop for index in indices for i from 0
                                for mask = (ash 1 (mod (+ (floor residue 2) (* i residue)) 8))
                                collect
                                `(when (< (+ base ,index) end)
                                   (%or-byte sap (the (unsigned-byte 64) (+ base ,index)) ,mask))))))
                  (values))))))
(define-sparse-resetters)
(defmacro sparse-dispatch (factor words)
  `(case (logand ,factor 15)
     ,@(loop for residue from 1 to 15 by 2
             collect `(,residue (,(intern (format nil "SPARSE-~D" residue))
                                ,words ,factor)))))

(defun run-sieve (sieve)
  (let* ((words (sieve-bits sieve)) (limit (sieve-limit sieve))
         )
    (declare (type words words) (type fixnum limit))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          unless (marked-p words (ash factor -1))
            do (dense-dispatch factor words
                 (sparse-dispatch factor words))))
  sieve)
(defun primep (sieve number)
  (declare (type fixnum number))
  (and (<= 2 number (the fixnum (sieve-limit sieve)))
       (or (= number 2)
           (and (oddp number)
                (not (marked-p (sieve-bits sieve) (ash number -1)))))))
(defun count-primes (sieve)
  (let* ((words (sieve-bits sieve)) (limit (sieve-limit sieve))
         (size (ceiling limit 2)) (full (ash size -6))
         (remainder (logand size 63)) (composites 0))
    (declare (type words words) (type fixnum limit size full remainder composites))
    (dotimes (i full) (incf composites (logcount (aref words i))))
    (when (plusp remainder)
      (incf composites
            (logcount (logand (aref words full)
                             (1- (ash 1 remainder))))))
    (+ (if (>= limit 2) 1 0) (- size composites))))
