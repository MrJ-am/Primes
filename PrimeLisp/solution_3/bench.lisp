;;;; Common measurement code. Keep identical across the two experiments.

(defpackage #:prime-bench
  (:use #:cl)
  (:export #:measure #:check-candidate #:reload-candidate #:main))
(in-package #:prime-bench)

(declaim (optimize (speed 1) (safety 2) (debug 2))
         (notinline prime-candidate:make-sieve prime-candidate:run-sieve
                    prime-candidate:primep prime-candidate:count-primes))

(defparameter *root* (truename "./"))
(defconstant +limit+ 1000000)

;; Linux flock: a failed concurrent measurement returns to the REPL immediately.
;; The descriptor is closed even when a condition escapes the measurement.
(sb-alien:define-alien-routine ("flock" %flock) sb-alien:int
  (fd sb-alien:int) (operation sb-alien:int))

(defun fresh-sieve (limit)
  (prime-candidate:run-sieve (prime-candidate:make-sieve limit)))

(defun reference-prime-p (n)
  ;; Independent trial-division oracle, used outside the timed region only.
  (and (>= n 2)
       (loop for d from 2 to (isqrt n) never (zerop (mod n d)))))

(defun check-candidate ()
  (dolist (limit '(0 1 2 3 4 9 10 25 49 63 64 65 100 121 127 128 129
                  255 256 257 511 512 513 1023 1024 1025))
    (let* ((sieve (fresh-sieve limit))
           (expected (loop for n from 0 to limit count (reference-prime-p n))))
      (assert (= expected (prime-candidate:count-primes sieve)))
      (loop for n from 0 to (1+ limit)
            do (assert (eq (not (null (prime-candidate:primep sieve n)))
                           (and (<= n limit) (reference-prime-p n)))
                       () "Incorrect primality flag: limit=~D n=~D" limit n))))
  (dolist (entry '((10000 . 1229) (100000 . 9592) (1000000 . 78498)))
    (assert (= (cdr entry)
               (prime-candidate:count-primes (fresh-sieve (car entry))))))
  (format *error-output* "~&Candidate validated (including 78,498 primes through 1,000,000).~%")
  t)

(defun reload-candidate ()
  "Compile and reload the canonical source in the current live image."
  (let ((output (merge-pathnames ".build/sieve.fasl" *root*)))
    (ensure-directories-exist output)
    (multiple-value-bind (fasl warnings failure)
        (compile-file (merge-pathnames "sieve.lisp" *root*) :output-file output)
      (declare (ignore warnings))
      (when failure (error "Candidate compilation failed."))
      (load fasl))))

(defun one-sample (seconds)
  (declare (type double-float seconds)
           (optimize (speed 3) (safety 1) (debug 1))
           (sb-ext:muffle-conditions sb-ext:compiler-note))
  (sb-ext:gc :full t)
  (let* ((units (float internal-time-units-per-second 1d0))
         (bytes-before (sb-ext:get-bytes-consed))
         (gc-before sb-ext:*gc-run-time*)
         (cpu-before (get-internal-run-time))
         (start (get-internal-real-time))
         (deadline (+ start (ceiling (* seconds units))))
         (finish start) (passes 0) (last-sieve nil))
    (declare (type fixnum bytes-before gc-before cpu-before start deadline finish passes)
             (type double-float units))
    (loop do (setf last-sieve (fresh-sieve +limit+))
             (incf passes)
             (setf finish (get-internal-real-time))
          until (>= finish deadline))
    (let* ((elapsed (/ (- finish start) units))
           (cpu (/ (- (get-internal-run-time) cpu-before) units))
           (gc (/ (- sb-ext:*gc-run-time* gc-before) units))
           (bytes (- (sb-ext:get-bytes-consed) bytes-before)))
      (assert (= 78498 (prime-candidate:count-primes last-sieve)))
      (list :passes passes :seconds elapsed :cpu-seconds cpu
            :microseconds-per-sieve (/ (* 1d6 elapsed) passes)
            :sieves-per-second (/ passes elapsed)
            :bytes-consed bytes :gc-seconds gc))))

(defun source-hashes ()
  (with-output-to-string (out)
    (let ((process (sb-ext:run-program
                    "/usr/bin/sha256sum"
                    (mapcar (lambda (name) (namestring (merge-pathnames name *root*)))
                            '("sieve.lisp" "bench.lisp" "bootstrap.lisp"))
                    :output out)))
      (assert (zerop (sb-ext:process-exit-code process))))))

(defun measure (&key (seconds 5d0) (repeats 3))
  "Validate, warm up, then measure complete fresh sieves; save all samples."
  (check-type seconds (real (0)))
  (check-type repeats (integer 1))
  (with-open-file (lock (or (sb-ext:posix-getenv "PRIMES_BENCH_LOCK")
                           "/tmp/primes-common-lisp-benchmark.lock")
                       :direction :io :if-exists :append :if-does-not-exist :create)
    (let ((fd (sb-sys:fd-stream-fd lock)))
      (unless (zerop (%flock fd 6)) ; LOCK_EX | LOCK_NB
        (error "Another measurement is running. Retry after it finishes."))
      (unwind-protect
           (progn
             (check-candidate)
             (fresh-sieve +limit+)
             (let* ((samples (loop repeat repeats collect (one-sample (float seconds 1d0))))
                    (times (sort (mapcar (lambda (s) (getf s :microseconds-per-sieve))
                                        samples) #'<))
                    (middle (floor repeats 2))
                    (median (if (oddp repeats) (nth middle times)
                                (/ (+ (nth (1- middle) times) (nth middle times)) 2)))
                    (record (list :utc-universal-time (get-universal-time)
                                  :method (or (sb-ext:posix-getenv "PRIMES_METHOD") "baseline")
                                  :sbcl (lisp-implementation-version)
                                  :machine (machine-version) :system (software-version)
                                  :cpu (sb-ext:posix-getenv "PRIMES_CPU")
                                  :mode (sb-ext:posix-getenv "PRIMES_MODE")
                                  :label prime-candidate:*name* :tags prime-candidate:*tags*
                                  :limit +limit+ :source-files-sha256 (source-hashes)
                                  :median-microseconds-per-sieve median :samples samples))
                    (path (merge-pathnames
                           (format nil "results/~D-~D.sexp" (get-universal-time)
                                   (random 1000000000)) *root*)))
               (ensure-directories-exist path)
               (with-open-file (out path :direction :output :if-exists :error)
                 (let ((*print-pretty* t) (*print-readably* t)) (write record :stream out))
                 (terpri out))
               (dolist (sample samples)
                 (format t "~A;~D;~,6F;1;~A~%" prime-candidate:*name*
                         (getf sample :passes) (getf sample :seconds)
                         prime-candidate:*tags*))
               (format *error-output* "~&Median: ~,3F us/sieve (~,1F sieves/s).~%Saved: ~A~%"
                       median (/ 1d6 median) path)
               record))
        (%flock fd 8))))) ; LOCK_UN

(defun main ()
  (if (equal (sb-ext:posix-getenv "PRIMES_MODE") "check")
      (check-candidate)
      (let ((*read-eval* nil))
        (multiple-value-bind (seconds end)
            (read-from-string (sb-ext:posix-getenv "PRIMES_SECONDS"))
          (assert (every (lambda (c) (find c '(#\Space #\Tab)))
                         (subseq (sb-ext:posix-getenv "PRIMES_SECONDS") end)))
          (measure :seconds seconds
                   :repeats (parse-integer (sb-ext:posix-getenv "PRIMES_REPEATS")))))))
