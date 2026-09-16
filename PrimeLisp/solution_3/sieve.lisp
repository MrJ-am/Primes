;;;; SPDX-License-Identifier: BSD-3-Clause
;;;; SBCL 2.6.8, Linux x86-64 with AVX2. One bit per odd candidate.
;;;; Native allocation/free, SIMD masks hoisted outside loops, cache blocking.
;;;; Dense/sparse patterns follow Mike Barber and GordonBGood (PrimeRust/solution_1).
;;;; No prime list or sieve result is precomputed. See README.md for the algorithm and development approach.
(defpackage #:prime-memory
  (:use #:cl) (:nicknames #:pm)
  (:export #:with-sieve #:run-sieve #:primep #:count-primes #:*name* #:*tags*))
(in-package #:prime-memory)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))
(defparameter *name* "cl")
(defparameter *tags* "algorithm=wheel,faithful=yes,bits=1")
(defun checked-limit (limit)
  (declare (optimize (safety 3)))
  (check-type limit (integer 0 #.most-positive-fixnum))
  limit)
(sb-alien:define-alien-routine ("malloc" allocate-storage) sb-alien:unsigned-long
  (size sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("free" release-storage) sb-alien:void
  (address sb-alien:unsigned-long))
(sb-alien:define-alien-routine ("memset" fill-storage) sb-alien:unsigned-long
  (address sb-alien:unsigned-long) (value sb-alien:int) (size sb-alien:unsigned-long))
(declaim (inline make-sieve-state))
(defstruct sieve-state
  (limit 0 :type fixnum) (word-count 0 :type fixnum)
  (address 0 :type (unsigned-byte 64)))
(defmacro with-sieve-state ((state limit) &body body)
  (let ((n (gensym)) (word-count (gensym)) (address (gensym)))
    `(let* ((,n (checked-limit ,limit)) (,word-count (ceiling (ceiling ,n 2) 64))
            (,address (allocate-storage (max 8 (* ,word-count 8)))))
       (declare (type fixnum ,n ,word-count) (type (unsigned-byte 64) ,address))
       (when (zerop ,address) (error "Native allocation failed."))
       (unwind-protect
            (let ((,state (make-sieve-state :limit ,n :word-count ,word-count :address ,address)))
              (declare (dynamic-extent ,state))
              (fill-storage ,address 0 (* ,word-count 8))
              (when (plusp ,word-count) (setf (sb-sys:sap-ref-64 (sb-sys:int-sap ,address) 0) 1))
              ,@body)
         (release-storage ,address)))))
(declaim (inline composite-flag-p))
(defun composite-flag-p (address index)
  (declare (type (unsigned-byte 64) address) (type fixnum index))
  (logbitp (logand index 63)
           (sb-sys:sap-ref-64 (sb-sys:int-sap address) (ash (ash index -6) 3))))

;; Mark an initial range of the sieve, preserving the factor's own prime flag.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown mark-initial-multiples! (sb-sys:system-area-pointer (unsigned-byte 64) (integer 3 129))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (mark-initial-multiples!)
    (:translate mark-initial-multiples!) (:policy :fast-safe)
    (:args (storage :scs (sb-vm::sap-reg) :to :save)
           (word-count :scs (sb-vm::unsigned-reg) :to :save))
    (:arg-types sb-vm::system-area-pointer sb-vm::unsigned-num (:constant (integer 3 129)))
    (:info factor)
    (:temporary (:sc sb-vm::sap-reg) cursor)
    (:temporary (:sc sb-vm::unsigned-reg) remaining scalar)
    (:temporary (:sc sb-vm::int-avx2-reg) m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 marked-flags)
    (:generator 1
      (let* ((masks (make-array factor :initial-element 0))
             (first (* factor (floor factor 128)))
             (block (* factor (if (<= factor 7) 4 1)))
             (vector-count (floor block 4))
             (registers (list m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14))
             (again (sb-assem:gen-label)) (tail (sb-assem:gen-label)))
        (dotimes (k 64)
          (let ((bit (+ (floor factor 2) (* k factor))))
            (setf (aref masks (floor bit 64))
                  (logior (aref masks (floor bit 64)) (ash 1 (mod bit 64))))))
        (let ((constants
                (loop for i below vector-count collect
                  (sb-c:register-inline-constant :avx2
                    (loop for lane below 4 sum
                      (ash (aref masks (mod (+ (* i 4) lane) factor)) (* lane 64)))))))
          (sb-assem:inst lea cursor (sb-vm::ea (* first 8) storage))
          (sb-vm::move remaining word-count)
          (unless (zerop first) (sb-assem:inst sub remaining first))
          (sb-assem:inst cmp remaining block)
          (sb-assem:inst jmp :b tail)
          (loop for reg in registers for constant in constants
                do (sb-assem:inst vmovdqu reg constant))
          (flet ((word (i)
                   (let ((mask (aref masks (mod i factor))))
                     (unless (zerop mask)
                       (if (typep mask '(signed-byte 32))
                           (sb-assem:inst or :qword (sb-vm::ea (* i 8) cursor) mask)
                           (progn (sb-assem:inst mov scalar mask)
                                  (sb-assem:inst or :qword (sb-vm::ea (* i 8) cursor) scalar)))))))
            (sb-assem:emit-label again)
            (dotimes (i vector-count)
              (if (< i (length registers))
                  (sb-assem:inst vpor marked-flags (nth i registers) (sb-vm::ea (* i 32) cursor))
                  (progn (sb-assem:inst vmovdqu marked-flags (sb-vm::ea (* i 32) cursor))
                         (sb-assem:inst vpor marked-flags marked-flags (nth i constants))))
              (sb-assem:inst vmovdqu (sb-vm::ea (* i 32) cursor) marked-flags))
            (loop for i from (* vector-count 4) below block do (word i))
            (sb-assem:inst add cursor (* block 8))
            (sb-assem:inst sub remaining block)
            (sb-assem:inst cmp remaining block)
            (sb-assem:inst jmp :ae again)
            (sb-assem:emit-label tail)
            (dotimes (i block)
              (unless (zerop (aref masks (mod i factor)))
                (let ((skip (sb-assem:gen-label)))
                  (sb-assem:inst cmp remaining i)
                  (sb-assem:inst jmp :be skip)
                  (word i) (sb-assem:emit-label skip)))))
          (let ((bit (floor factor 2)))
            (sb-assem:inst mov scalar (logxor #xffffffffffffffff (ash 1 (mod bit 64))))
            (sb-assem:inst and :qword (sb-vm::ea (* 8 (floor bit 64)) storage) scalar))
          (sb-assem:inst vzeroupper))))))

;; Mark a later range aligned to the factor's period. The factor lies before it.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown mark-block-multiples! (sb-sys:system-area-pointer (unsigned-byte 64) (integer 3 129))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (mark-block-multiples!)
    (:translate mark-block-multiples!) (:policy :fast-safe)
    (:args (storage :scs (sb-vm::sap-reg) :to :save)
           (word-count :scs (sb-vm::unsigned-reg) :to :save))
    (:arg-types sb-vm::system-area-pointer sb-vm::unsigned-num (:constant (integer 3 129)))
    (:info factor)
    (:temporary (:sc sb-vm::sap-reg) cursor)
    (:temporary (:sc sb-vm::unsigned-reg) remaining scalar)
    (:temporary (:sc sb-vm::int-avx2-reg) m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 marked-flags)
    (:generator 1
      (let* ((masks (make-array factor :initial-element 0))
             (first 0)
             (block (* factor (if (<= factor 7) 4 1)))
             (vector-count (floor block 4))
             (registers (list m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12 m13 m14))
             (again (sb-assem:gen-label)) (tail (sb-assem:gen-label)))
        (dotimes (k 64)
          (let ((bit (+ (floor factor 2) (* k factor))))
            (setf (aref masks (floor bit 64))
                  (logior (aref masks (floor bit 64)) (ash 1 (mod bit 64))))))
        (let ((constants
                (loop for i below vector-count collect
                  (sb-c:register-inline-constant :avx2
                    (loop for lane below 4 sum
                      (ash (aref masks (mod (+ (* i 4) lane) factor)) (* lane 64)))))))
          (sb-assem:inst lea cursor (sb-vm::ea (* first 8) storage))
          (sb-vm::move remaining word-count)
          (unless (zerop first) (sb-assem:inst sub remaining first))
          (sb-assem:inst cmp remaining block)
          (sb-assem:inst jmp :b tail)
          (loop for reg in registers for constant in constants
                do (sb-assem:inst vmovdqu reg constant))
          (flet ((word (i)
                   (let ((mask (aref masks (mod i factor))))
                     (unless (zerop mask)
                       (if (typep mask '(signed-byte 32))
                           (sb-assem:inst or :qword (sb-vm::ea (* i 8) cursor) mask)
                           (progn (sb-assem:inst mov scalar mask)
                                  (sb-assem:inst or :qword (sb-vm::ea (* i 8) cursor) scalar)))))))
            (sb-assem:emit-label again)
            (dotimes (i vector-count)
              (if (< i (length registers))
                  (sb-assem:inst vpor marked-flags (nth i registers) (sb-vm::ea (* i 32) cursor))
                  (progn (sb-assem:inst vmovdqu marked-flags (sb-vm::ea (* i 32) cursor))
                         (sb-assem:inst vpor marked-flags marked-flags (nth i constants))))
              (sb-assem:inst vmovdqu (sb-vm::ea (* i 32) cursor) marked-flags))
            (loop for i from (* vector-count 4) below block do (word i))
            (sb-assem:inst add cursor (* block 8))
            (sb-assem:inst sub remaining block)
            (sb-assem:inst cmp remaining block)
            (sb-assem:inst jmp :ae again)
            (sb-assem:emit-label tail)
            (dotimes (i block)
              (unless (zerop (aref masks (mod i factor)))
                (let ((skip (sb-assem:gen-label)))
                  (sb-assem:inst cmp remaining i)
                  (sb-assem:inst jmp :be skip)
                  (word i) (sb-assem:emit-label skip)))))
          (sb-assem:inst vzeroupper))))))


(defmacro define-small-markers (range)
  (let ((operation (ecase range
                     (:initial 'mark-initial-multiples!)
                     (:block 'mark-block-multiples!)))
        (dispatcher (intern (format nil "MARK-~A-SMALL-FACTOR" range))))
    `(progn
       ,@(loop for p from 3 to 129 by 2 collect
         `(defun ,(intern (format nil "MARK-~A-BY-~D" range p)) (address word-count)
            (declare (type (unsigned-byte 64) address) (type fixnum word-count))
            (,operation (sb-sys:int-sap address) word-count ,p)
            nil))
       (defun ,dispatcher (address word-count factor)
         (declare (type (unsigned-byte 64) address) (type fixnum word-count factor))
         (case factor
           ,@(loop for p from 3 to 129 by 2 collect
             `(,p (,(intern (format nil "MARK-~A-BY-~D" range p)) address word-count))))))))
(define-small-markers :initial)
(define-small-markers :block)

;; Factors 3 and 5 have already marked their multiples. For a later factor,
;; visit only odd cofactors coprime to 30. The byte-mask phase repeats after
;; 240 cofactors: 64 writes in 15 * factor bytes, instead of 120 writes.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (sb-c:defknown mark-remaining-multiples!
      (sb-sys:system-area-pointer sb-sys:system-area-pointer
       (unsigned-byte 64) (unsigned-byte 64) (integer 1 15))
      (values) (sb-c:always-translatable) :overwrite-fndb-silently t)
  (sb-c:define-vop (mark-remaining-multiples!)
    (:translate mark-remaining-multiples!) (:policy :fast-safe)
    (:args (storage :scs (sb-vm::sap-reg) :to :save)
           (end :scs (sb-vm::sap-reg) :to :save)
           (byte-stride :scs (sb-vm::unsigned-reg) :to :save)
           (period :scs (sb-vm::unsigned-reg) :to :save))
    (:arg-types sb-vm::system-area-pointer sb-vm::system-area-pointer
                sb-vm::unsigned-num sb-vm::unsigned-num (:constant (integer 1 15)))
    (:info residue)
    (:temporary (:sc sb-vm::sap-reg) cursor full-end tail-address)
    (:temporary (:sc sb-vm::unsigned-reg) stride-3 stride-5 stride-7)
    (:generator 1
      (let ((again (sb-assem:gen-label)) (tail (sb-assem:gen-label))
            (done (sb-assem:gen-label)))
        (flet ((mark-period (bounded)
                 (dotimes (group 30)
                   (loop for low from 1 to 7 by 2
                         for index in (list byte-stride stride-3 stride-5 stride-7)
                         for cofactor = (+ (* group 8) low)
                         unless (or (zerop (mod cofactor 3)) (zerop (mod cofactor 5))) do
                     (let ((carry (floor (* cofactor residue) 16))
                           (mask (ash 1 (mod (floor (* cofactor residue) 2) 8))))
                       (if bounded
                           (progn
                             (sb-assem:inst lea tail-address (sb-vm::ea carry cursor index))
                             (sb-assem:inst cmp tail-address end)
                             (sb-assem:inst jmp :ae done)
                             (sb-assem:inst or :byte (sb-vm::ea 0 tail-address) mask))
                           (sb-assem:inst or :byte (sb-vm::ea carry cursor index) mask))))
                   (sb-assem:inst lea cursor (sb-vm::ea 0 cursor byte-stride 8)))
                 (sb-assem:inst add cursor (* 15 residue))))
          (sb-vm::move cursor storage)
          (sb-assem:inst lea stride-3 (sb-vm::ea 0 byte-stride byte-stride 2))
          (sb-assem:inst lea stride-5 (sb-vm::ea 0 byte-stride byte-stride 4))
          (sb-assem:inst lea stride-7 (sb-vm::ea 0 stride-3 byte-stride 4))
          ;; Last offset = floor(239 * factor / 16) = period - byte-stride - 1.
          (sb-vm::move full-end end)
          (sb-assem:inst sub full-end period)
          (sb-assem:inst jmp :b tail)
          (sb-assem:inst lea full-end (sb-vm::ea 1 full-end byte-stride))
          (sb-assem:inst cmp cursor full-end)
          (sb-assem:inst jmp :ae tail)
          (sb-assem:emit-alignment 4 :long-nop)
          (sb-assem:emit-label again)
          (mark-period nil)
          (sb-assem:inst cmp cursor full-end)
          (sb-assem:inst jmp :b again)
          (sb-assem:emit-label tail)
          (mark-period t)
          (sb-assem:emit-label done))))))

(defmacro define-remaining-markers ()
  `(progn
     ,@(loop for r from 1 to 15 by 2 collect
       `(defun ,(intern (format nil "MARK-REMAINING-RESIDUE-~D" r)) (address begin byte-count factor)
          (declare (type (unsigned-byte 64) address) (type fixnum begin byte-count)
                   (type (integer 131 2147483647) factor))
          (let* ((period (* 15 factor))
                 (start (max (* (floor factor 240) period)
                             (if (zerop begin) 0
                                 (the fixnum (* (floor begin period) period)))))
                 (storage (sb-sys:int-sap address)))
            (declare (type (unsigned-byte 59) period start))
            (mark-remaining-multiples! (sb-sys:sap+ storage start)
                                      (sb-sys:sap+ storage byte-count)
                                      (ash factor -4) period ,r)
            ;; The first period includes the factor itself (cofactor 1).
            (when (zerop start)
              (let* ((offset (ash factor -4))
                     (mask (logxor 255 (ash 1 (logand (ash factor -1) 7)))))
                (setf (sb-sys:sap-ref-8 storage offset)
                      (logand (sb-sys:sap-ref-8 storage offset) mask)))))
          nil))
     (defun mark-remaining-factor (address begin byte-count factor)
       (declare (type (unsigned-byte 64) address) (type fixnum begin byte-count factor))
       (case (logand factor 15)
         ,@(loop for r from 1 to 15 by 2 collect
             `(,r (,(intern (format nil "MARK-REMAINING-RESIDUE-~D" r))
                    address begin byte-count factor)))))))
(define-remaining-markers)

(defparameter *words-per-block* 4096)
(defun mark-composites (state)
  (let ((address (sieve-state-address state)) (word-count (sieve-state-word-count state))
        (limit (sieve-state-limit state)) (block-size *words-per-block*))
    (declare (type fixnum block-size))
    ;; The first block determines the factors by sieving, with no stored prime list.
    ;; For supported sizes (<=10 million), every factor flag lies in the first block.
    (assert (>= (* block-size 128) (isqrt limit)))
    (loop for begin fixnum from 0 below word-count by block-size
          for end fixnum = (min word-count (+ begin block-size)) do
      (loop for factor fixnum from 3 to (isqrt (min limit (* end 128))) by 2
            unless (composite-flag-p address (ash factor -1)) do
        (cond ((zerop begin)
               (if (<= factor 129) (mark-initial-small-factor address end factor)
                   (mark-remaining-factor address 0 (ash end 3) factor)))
              ((<= factor 129)
               ;; A bounded overlap preserves the factor's repeating mask phase.
               ;; Only composites are written; no prime bit is cleared in later blocks.
               (let ((base (* (floor begin factor) factor)))
                 (declare (type fixnum base))
                 (mark-block-small-factor (+ address (ash base 3)) (- end base) factor)))
              (t (mark-remaining-factor address (ash begin 3) (ash end 3) factor))))))
  state)

(defun sieve-prime-p (state number)
  (declare (type fixnum number))
  (and (<= 2 number (sieve-state-limit state))
       (or (= number 2) (and (oddp number)
         (not (composite-flag-p (sieve-state-address state) (ash number -1)))))))
(defun count-sieve-primes (state)
  (let* ((limit (sieve-state-limit state)) (storage (sb-sys:int-sap (sieve-state-address state)))
         (candidate-count (ceiling limit 2)) (word-count (ash candidate-count -6)) (tail (logand candidate-count 63)))
    (declare (type fixnum limit candidate-count word-count tail))
    (+ (if (>= limit 2) 1 0)
       (- candidate-count (+ (loop for i fixnum below word-count sum
                   (logcount (sb-sys:sap-ref-64 storage (ash i 3))) fixnum)
                  (if (zerop tail) 0
                    (logcount (logand (sb-sys:sap-ref-64 storage (ash word-count 3))
                                     (1- (ash 1 tail))))))))))


(defmacro with-sieve ((state limit) &body body)
  "Create fresh state; release native memory on normal and nonlocal exits.
STATE and its address must not escape BODY. No finalizer or GC is needed."
  `(with-sieve-state (,state ,limit) ,@body))
(declaim (inline run-sieve primep count-primes))
(defun run-sieve (state) (mark-composites state))
(defun primep (state number) (sieve-prime-p state number))
(defun count-primes (state) (count-sieve-primes state))
