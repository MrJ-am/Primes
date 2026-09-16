# Common Lisp wheel sieve by MrJ-am

Tags: `algorithm=wheel,faithful=yes,bits=1`; one thread.

Dense AVX2 kernels handle small factors. For sparse factors, a cofactor wheel
skips multiples already eliminated by 3 and 5: 64 writes cover a 240-cofactor
period. A 32 KiB block traversal bounds the active working set. Dense masks and
sparse phases are generated from arithmetic identities, not a stored prime list.

This SBCL 2.6.8 entry targets Linux x86-64 with AVX2.
Each pass creates fresh state and a dynamically sized native buffer. `unwind-protect`
releases it even on a nonlocal exit; libc supplies allocation, zeroing and release.
The sieve, timing and pass counting are implemented in Lisp and local SBCL VOPs.
No previous pass's results are retained.

## Run

```sh
./run.sh batch 5 1
./run.sh check
./run.sh repl
docker build -t primes-lisp-wheel .
docker run --rm primes-lisp-wheel
```

The Dockerfile bootstraps the pinned SBCL release from verified source. `SBCL`
can select a local executable. Compilation and validation occur before timing.
In the REPL, `(prime-bench:measure 5 3)` takes three samples. `pm:with-sieve`,
`pm:run-sieve`, `pm:primep` and `pm:count-primes` expose the implementation;
state and native addresses must not escape the `with-sieve` body.

## Results

One observed sample on AMD EPYC 9V74, Linux x86-64:

```text
mrj-am-cl-wheel;96600;5.000145000;1;algorithm=wheel,faithful=yes,bits=1
```

See [the category comparison](../../benchmarks/wheel/README.md).
The check compares all flags with an independent byte sieve, tests allocation
lifetimes and memory guards, and verifies 664,579 primes through ten million.

## Credits and development

Dense/sparse patterns follow Mike Barber and GordonBGood's
[Rust solution 1](../../PrimeRust/solution_1). The high-level dense generator
also follows Robert Mayer's practice of applying individual bits to a local word.
The native-memory and VOP implementation extends our original Lisp solution 3.
A separate entry preserves the existing solutions' algorithm categories and
runtime requirements.

Development used ChatGPT/Codex to transfer and test ideas between C, Rust and
Common Lisp. Rejected experiments were excluded from the submitted kernels.
Each language implements its own sieve, allocation lifecycle, timer and pass
counter; Python only launches separate executables for comparison. No completed
sieve or prime list is reused between passes.
