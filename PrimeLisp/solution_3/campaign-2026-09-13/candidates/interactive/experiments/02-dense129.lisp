;;;; One bit per odd candidate, held in native 64-bit words.
(defpackage #:prime-candidate
  (:use #:cl)
  (:export #:make-sieve #:run-sieve #:primep #:count-primes #:*tags* #:*name*))
(in-package #:prime-candidate)
(declaim (optimize (speed 3) (safety 0) (debug 1)))
(defparameter *name* "echologie-cl-dense129")
(defparameter *tags* "algorithm=base,faithful=yes,bits=1")
(deftype words () '(simple-array (unsigned-byte 64) (*)))
(defclass word-sieve ()
  ((limit :initarg :limit :reader sieve-limit :type fixnum)
   (bits :initarg :bits :reader sieve-bits :type words)))
(defun make-sieve (limit)
  (check-type limit (integer 0 #.most-positive-fixnum))
  (let ((bits (make-array (ceiling (ceiling limit 2) 64)
                          :element-type '(unsigned-byte 64) :initial-element 0)))
    (declare (type words bits))
    (when (plusp (length bits)) (setf (aref bits 0) 1))
    (make-instance 'word-sieve :limit limit :bits bits)))
(declaim (inline marked-p mark-bit))
(defun marked-p (bits index)
  (declare (type words bits) (type fixnum index))
  (logbitp (logand index 63) (aref bits (ash index -6))))
(defun mark-bit (bits index)
  (declare (type words bits) (type fixnum index))
  (let ((word (ash index -6))
        (mask (the (unsigned-byte 64) (ash 1 (logand index 63)))))
    (setf (aref bits word) (logior (aref bits word) mask))))
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

(defun run-sieve (sieve)
  (let* ((bits (sieve-bits sieve)) (limit (sieve-limit sieve))
         (end (ceiling limit 2)))
    (declare (type words bits) (type fixnum limit end))
    (loop for factor fixnum from 3 to (isqrt limit) by 2
          unless (marked-p bits (ash factor -1))
            do (if (<= factor 129) (dense-reset bits factor)
                   (loop for index fixnum from (ash (* factor factor) -1)
                         below end by factor do (mark-bit bits index)))))
  sieve)
(defun primep (sieve number)
  (declare (type fixnum number))
  (and (<= 2 number (the fixnum (sieve-limit sieve)))
       (or (= number 2)
           (and (oddp number)
                (not (marked-p (sieve-bits sieve) (ash number -1)))))))
(defun count-primes (sieve)
  (let* ((limit (sieve-limit sieve)) (bits (sieve-bits sieve))
         (nbits (ceiling limit 2)) (nwords (ash nbits -6))
         (tail (logand nbits 63)))
    (declare (type words bits) (type fixnum limit nbits nwords tail))
    (+ (if (>= limit 2) 1 0)
       (- nbits
          (+ (loop for i fixnum below nwords sum (logcount (aref bits i)) fixnum)
             (if (zerop tail) 0
                 (logcount (logand (aref bits nwords) (1- (ash 1 tail))))))))))
