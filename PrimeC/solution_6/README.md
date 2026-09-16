# C base sieve by MrJ-am

Tags: `algorithm=base,faithful=yes,bits=1`; one thread.

The outer loop scans every odd candidate. Dense kernels expand individual
single-bit ORs in increasing multiple order; GCC can then fold and vectorize
these operations. Larger factors use eight byte writes per period. Their
addresses separate a runtime stride from constant carries. This follows the
accepted dense/sparse approach in Rust solution 1: period alignment can touch
earlier composites, and the dense kernel restores the factor's own bit.

A fresh struct and dynamically sized zeroed buffer are created for each pass.
Allocation, initialization and marking are timed. Validation is performed on
the final state after the timer is read. The byte/word representation assumes
little endian; the supplied build flags target x86-64.

## Run

```sh
./run.sh              # GCC, five seconds, limit 1,000,000
./run.sh check        # every flag against an independent sieve; count at 10M
docker build -t primes-c-base .
docker run --rm primes-c-base
```

`./sieve 10` runs an already built binary for ten seconds. Run it from this
directory so `author.txt` is available. Requires GCC and a POSIX clock.

## Results

One observed sample on AMD EPYC 9V74, Linux x86-64:

```text
MrJ-am-c-base;67892;5.000042245;1;algorithm=base,faithful=yes,bits=1
```

See [the category comparison](../../benchmarks/base/README.md) for
commands, raw samples and the limits of the comparison.

## Credits and development

Dense/sparse marking derives from Mike Barber and GordonBGood's
[original Rust solution](../../PrimeRust/solution_1). Address decomposition
and the cofactor wheel were developed with the Common Lisp native-storage entry.
The new C entry keeps these kernels isolated from the independent existing C
solutions and their tuning infrastructure.

Development used ChatGPT/Codex to transfer and test ideas between C, Rust and
Common Lisp. Rejected experiments were excluded from the submitted kernels.
Each language implements its own sieve, allocation lifecycle, timer and pass
counter; Python only launches separate executables for comparison. No completed
sieve or prime list is reused between passes.
