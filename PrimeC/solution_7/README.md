# C wheel sieve by MrJ-am

Tags: `algorithm=wheel,faithful=yes,bits=1`; one thread.

The first factors use dense single-bit kernels. After factors 3 and 5 have
been applied, sparse marking visits only cofactors coprime to 30. The byte-mask
phase repeats after 240 cofactors, giving 64 writes instead of 120. A 32 KiB
block traversal keeps the active data in cache. A bounded overlap aligns each
block with the factor's period; the first period restores the prime itself.

A fresh struct and dynamically sized zeroed buffer are created for each pass.
Allocation, initialization and marking are timed. Validation is performed on
the final state after the timer is read. The byte/word representation assumes
little endian; the supplied build flags target x86-64.

## Run

```sh
./run.sh              # GCC, five seconds, limit 1,000,000
./run.sh check        # every flag against an independent sieve; count at 10M
docker build -t primes-c-wheel .
docker run --rm primes-c-wheel
```

`./sieve 10` runs an already built binary for ten seconds. Run it from this
directory so `author.txt` is available. Requires GCC and a POSIX clock.

## Results

One observed sample on AMD EPYC 9V74, Linux x86-64:

```text
MrJ-am-c-wheel;66712;5.000008508;1;algorithm=wheel,faithful=yes,bits=1
```

See [the category comparison](../../benchmarks/wheel/README.md) for
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
