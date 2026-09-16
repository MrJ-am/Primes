# Lisp/Rust ping-pong: a sparse cofactor wheel

Both implementations improve in this exchange. Lisp's median throughput rises
by **29.6%**, Rust's by **9.3%**, and the new Lisp leads the new Rust by **13.3%**
in the final campaign. The improvement was developed in Lisp and transferred
to Rust, then adapted to Rust's generated code.

The baseline is `3791e30368de8d11e906eb88a6be82eadea0542c`: this already contains
the optimized Rust from the [preceding campaign](README.md). "Rust before"
below does **not** mean Mike Barber's original, unmodified implementation.
Gains from separate campaigns are not compounded.

## Results

Final campaign on 2026-09-16, eight five-second samples per implementation:

| Implementation | Median passes/s | Minimum | Maximum | Gain over its own baseline |
| --- | ---: | ---: | ---: | ---: |
| Lisp before | 15,108.3 | 13,713.4 | 16,090.2 | — |
| Lisp after | 19,582.5 | 18,503.7 | 19,963.8 | +29.6% |
| Rust before | 15,818.2 | 12,651.7 | 16,443.2 | — |
| Rust after | 17,286.0 | 16,103.7 | 17,825.5 | +9.3% |

The new Lisp leads the new Rust in all eight paired rounds, by 5.3–17.8%.
Their observed ranges do not overlap. Lisp also beats its own baseline in
all eight rounds; Rust beats its baseline in seven, losing one by 2.1%.
The particularly slow Rust baseline sample in round eight is retained.
No samples were removed. Percentages in the table are ratios of medians,
not averages of paired percentage gains.

All 32 samples validate the expected count of 78,498 primes. The
[complete raw data](2026-09-16-ping-pong.json) preserve every sample's output,
commands, compiler versions, source and binary hashes, and timing metadata.
These are measurements of these implementations on this machine, not a
general ranking of Rust and Lisp.

## What changed

Both implementations keep 32 KiB blocks and one bit per odd candidate. Dense
marking for factors up to 129 is unchanged. For larger factors, multiples
whose cofactor is divisible by 3 or 5 have already been marked. The sparse
kernels now skip those redundant writes.

For an odd factor `p = 16*q + r`, a mask period considers the odd cofactors
`m` between 1 and 239 that are coprime to 30. There are 64 such cofactors.
The byte offset is `m*q + floor(m*r/16)` and the single-bit mask is
`1 << (floor(m*r/2) % 8)`. Advancing by `15*p` bytes repeats the phase.
Thus a complete period performs 64 writes instead of 120: **46.7% fewer
sparse writes**, not a claim of 46.7% less work for the entire sieve.

The starting period is
`max(floor(p/240), floor(begin_bytes/(15*p))) * (15*p)`.
An overlap can revisit earlier composites. If the first period includes the
prime factor itself, its bit is restored afterward. These masks encode
divisibility, not precomputed prime results; factors are discovered anew
from each pass's sieve.

- **Lisp:** macros generate eight residue-specialized functions. An SBCL VOP
  walks the period with a cursor and register strides `q`, `3*q`, `5*q`, and
  `7*q`. Full periods use a pointer bound derived from the last selected
  offset, `15*p - q - 1`. The tail checks addresses in increasing order and
  exits at the first address outside the buffer. Obsolete sparse kernels were
  removed and duplicate dense-wrapper generation was consolidated.
- **Rust:** const generics compute the cofactor, carry and mask constants.
  The first port materialized a 64-entry runtime address table and loaded
  masks inside the loop. The retained version explicitly expands the 64
  complete-period writes so each mask is a compile-time constant. A bounded
  loop handles the tail. The factor scan also uses a simple `while` loop.
  The existing ordinary sparse resetter remains available to other variants,
  including the extreme hybrid implementation. No Rust assembly was added.

This is a wheel used for marking, rather than compressed wheel storage.
The two new implementations therefore report
`algorithm=wheel,faithful=yes,bits=1`; the baselines reported
`algorithm=other,faithful=yes,bits=1`. Other Rust variants retain their tags.
Each pass still constructs fresh state, initializes it, sieves and releases
it. There is no prime list or completed sieve shared between passes.

Exploratory changes to dense marking, block sizes, loop alignment and sparse
unrolling did not establish a stable additional gain and were discarded.
The results above compare the complete retained changes; they do not isolate
the individual contribution of each source edit.

## Measurement protocol

- Linux x86-64 virtual machine, AMD EPYC 9V74, pinned to logical CPU 0.
- Rust 1.98.1 and SBCL 2.6.8. Both Rust binaries use the same release profile
  and repository `.cargo/config`: native CPU, AVX-512 disabled. Lisp uses
  AVX2 kernels. These are specialized implementations, not portable defaults.
- Limit 1,000,000, one thread, eight separate five-second samples for each
  of four versions. All Rust builds and correctness suites finish before the
  campaign; no other benchmark or build runs alongside a timed sample.
  Lisp compilation and validation run before its timer.
- For each rotation of the four-version order, the harness runs it forward
  and backward. Over eight rounds, every version occupies every position
  exactly twice. This balances position without eliminating variation in a
  shared virtual machine.
- Throughput is passes divided by the reported elapsed time. Allocation,
  initialization and release are included in each timed loop, except that
  validation and release of the final retained sieve follow the last timestamp,
  as in the baselines. Lisp reports zero Lisp heap bytes and zero GC time;
  native buffer allocation remains part of the work.

## Correctness checks

Both Rust debug and release suites pass all 23 binary tests. The independent
byte-sieve oracle compares every odd flag, including limits around prime
squares, sparse wheel periods and block boundaries, through 2,000,003.
Known-count tests cover 10,000,000. The helper-macro doctest passes; its
pre-existing incomplete example remains ignored.

Lisp's `./run.sh check` passes the independent full-flag comparisons, separate
state lifetimes, native-memory guards, block boundaries and the count of
664,579 at 10,000,000. Added cases exercise the dense/sparse transition and
period boundaries around 131², 131×239, 239², 241², 241×479, 479², 487²,
719², 727² and 997². All final benchmark source hashes match these tested files.

The Docker image pinned to Rust 1.57 was not tested; the measured compiler
is Rust 1.98.1. No successful Valgrind run is claimed. Lisp depends on the
specified SBCL internals and AVX2-capable Linux x86-64 hardware.

## Source provenance

The raw data record local source commit
`30139439c2422e768019801208fb5248e218b14b`. Publication recreates commit metadata
through the GitHub connector. The corresponding published source commit is
`99b81f7327882a06b817d39a1f899714efe97ac9`; both have the identical Git tree
`b987a436c561ac120bd3e88ce6bd5ef7b46fd7d6`.
Documentation and raw results are added in the following commit, with no
further change to the measured sources.

## Reproduce

Use the same machine, Rust compiler and flags for both Rust builds, with
Python 3 and SBCL 2.6.8 installed. From the candidate repository root:

```sh
git worktree add --detach ../primes-ping-pong-baseline 3791e30368de8d11e906eb88a6be82eadea0542c
cd ../primes-ping-pong-baseline/PrimeRust/solution_1
CARGO_TARGET_DIR="$PWD/target" cargo build --release --locked
```

In the candidate checkout's `PrimeRust/solution_1` directory:

```sh
CARGO_TARGET_DIR="$PWD/target" cargo test --release --locked
CARGO_TARGET_DIR="$PWD/target" cargo test --locked
CARGO_TARGET_DIR="$PWD/target" cargo build --release --locked
(cd ../../PrimeLisp/solution_3 && ./run.sh check)
python3 benchmarks/compare.py \
  --original /absolute/path/to/primes-ping-pong-baseline/PrimeRust/solution_1/target/release/prime-sieve-rust \
  --candidate target/release/prime-sieve-rust \
  --baseline-ref 3791e30368de8d11e906eb88a6be82eadea0542c \
  --lisp /absolute/path/to/primes-ping-pong-baseline/PrimeLisp/solution_3 \
  --lisp-candidate ../../PrimeLisp/solution_3 \
  --cpu 0 --seconds 5 --repeats 8 --output benchmarks/local-ping-pong.json
```

Replace CPU 0 with an allowed logical CPU if necessary. Set `SBCL` for the
standalone Lisp check and `--sbcl` for the comparison if SBCL is not on `PATH`.
The JSON key `rust_original` denotes the already optimized Rust baseline of
this exchange; `lisp` denotes its unchanged Lisp baseline.
