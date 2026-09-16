# Rust other sieve by MrJ-am

Tags: `algorithm=other,faithful=yes,bits=1`; one thread.

The sieve traverses 32 KiB cache blocks, rediscovering factors in the current
pass's storage. Marking remains dense/sparse, with every odd multiple visited.
The reordered block traversal is conservatively tagged `other`: it changes the
global factor-by-factor traversal prescribed for `base`. It uses no cofactor wheel.

Small factors use const-generic dense marking; larger factors use byte kernels
whose runtime stride is separated from constant address carries. Each pass
allocates a fresh zeroed `Box<[u64]>` in a new sieve state. The final state is
counted after timing; `black_box` makes the completed state observable in every
pass. No sieve or prime list survives between passes.

## Run

```sh
./run.sh              # Rust 1.98.1, five seconds, limit 1,000,000
./run.sh check        # independent full-flag oracle and 10M count
docker build -t primes-rust-other .
docker run --rm primes-rust-other
```

`./sieve 10` runs an already built binary for ten seconds. There are no Cargo
package dependencies. The supplied build uses native x86-64 instructions with
AVX-512 disabled, matching the original Rust solution 1 comparison. Byte/word
aliasing requires little endian.

## Results

One observed sample on AMD EPYC 9V74, Linux x86-64:

```text
MrJ-am-rust-other;82020;5.000042786;1;algorithm=other,faithful=yes,bits=1
```

See [the category comparison](../../benchmarks/other/README.md).

## Credits and development

The marking kernels derive from Mike Barber and GordonBGood's
[Rust solution 1](../../PrimeRust/solution_1). Cache blocking, sparse address
decomposition and the cofactor wheel were transferred from the native-storage
Common Lisp experiments. This separate entry preserves solution 1's `base`
algorithms and tags, and lets this algorithm category be reviewed independently.

Development used ChatGPT/Codex to transfer and test ideas between C, Rust and
Common Lisp. Rejected experiments were excluded from the submitted kernels.
Each language implements its own sieve, allocation lifecycle, timer and pass
counter; Python only launches separate executables for comparison. No completed
sieve or prime list is reused between passes.
