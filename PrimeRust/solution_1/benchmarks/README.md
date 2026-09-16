# Transferring cache blocking from Common Lisp to Rust

This page records the first Rust optimization campaign. The next exchange is
documented in [Lisp/Rust ping-pong](ping-pong.md).

The experiment starts from `c8fa14d3e67835258ddd15230b8be6b9d77d4c48`,
which includes the final Common Lisp solution 3 and the unchanged Mike Barber
`bit-unrolled-hybrid` Rust implementation. Candidate source is published as
`515d505ce32d8ddcac0f5410752ce25b59c46862`.

The raw benchmark logs retain the local commit IDs recorded during measurement.
Publication through the GitHub connector recreated commit metadata, with
identical Git trees for both measured source versions:

| Measured source | Local commit in the logs | Published commit |
| --- | --- | --- |
| Cache blocking only | `01e90d7a38090b70f2f3d0e22aa70f3cb3c20967` | `7afadce8fb07f977e6a84d58445a5064f9b2703c` |
| Final candidate | `048437508fae97feda3f681c4d9130345928c8cf` | `515d505ce32d8ddcac0f5410752ce25b59c46862` |

The retained change completes each 32 KiB block before moving forward. Factor
flags come from the current pass's first block. The original dense and sparse
marking loops are preserved, with their first marking period aligned to the
block boundary. Allocation, zero initialization, marking, and release remain
inside the timed loop; the last sieve is validated and released after timing,
as in the original programs.

The second retained change transfers the Lisp sparse kernel's address
decomposition: a runtime stride plus compile-time carries determined by the
factor modulo 16. In particular, the first period uses `skip / 16` instead of
`(skip * skip / 16) / skip`. This preserves every address while avoiding a
division by a runtime factor.

## Results

Final alternating campaign, 2026-09-16:

| Implementation | Median passes/s | Minimum | Maximum | Median microseconds/pass |
| --- | ---: | ---: | ---: | ---: |
| Original Rust | 13,834.1 | 13,597.9 | 14,257.1 | 72.285 |
| Common Lisp solution 3 | 15,556.2 | 15,350.8 | 16,026.6 | 64.283 |
| Modified Rust | 16,261.5 | 15,688.8 | 16,659.4 | 61.495 |

The candidate's median throughput is **17.5% above the original Rust** and
**4.5% above Lisp**. It leads Lisp in each of the five paired rounds, though
the ranges overlap and the smallest paired lead is only about 0.5%. This is
a modest local advantage, not a claim that every run or machine will favor
Rust. All fifteen samples validate the expected prime count.

[Complete final samples and metadata](2026-09-16-epyc.json) include the exact
commands, versions and hashes. An earlier
[cache-blocking-only campaign](2026-09-16-cache-blocking-only.json) measured
medians of 14,386.5 passes/s for original Rust, 16,100.8 for Lisp and 16,731.0
for blocked Rust. The changing absolute rates illustrate environmental
variation. These separate campaigns do not isolate the small address change's
individual speedup; most of the improvement already appeared with blocking.

Exploratory trials also covered word-mask folding, wider small-factor loops,
16/30 KiB blocks, additional sparse specialization and cache-line alignment.
They did not establish an additional gain and were discarded. Only the final
alternating campaign above is used for the final performance comparison.

## Measurement protocol

- Linux x86-64 virtual machine, AMD EPYC 9V74, logical CPU 0.
- Rust 1.98.1 and SBCL 2.6.8; both Rust binaries built with the same release
  profile and the original `.cargo/config`: native CPU, AVX-512 disabled.
- Sieve limit 1,000,000, one thread, fresh state on every pass, one bit per odd
  candidate, with the count of 78,498 checked after each sample.
- Five separate five-second samples of each implementation. Order is rotated
  and reversed between rounds; no builds or other benchmarks run alongside
  the measurements. Lisp compilation and validation are outside its timer.
- Medians are taken over passes divided by each sample's reported duration.
  Results are local measurements in a shared virtualized environment, not a
  general ranking of the two languages or of other CPU architectures.

The Rust baseline retains its original `algorithm=base` output tag. The
candidate is tagged `algorithm=other`, like Lisp solution 3, because the outer
traversal is now blocked. All three report `faithful=yes,bits=1` and one thread.

## Validation

`cargo test --release` passes all 23 binary tests, including the existing
known-count tests up to 10,000,000 and a new independent byte-sieve oracle that
compares every odd flag for small limits, prime squares, block boundaries,
prime upper limits, and 2,000,003. The full suite also passes in a debug build,
where bounds and debug assertions are active. The helper-macro
doctest passes; its illustrative incomplete example remains ignored.

Memcheck was attempted but could not initialize against this environment's
dynamic loader because a mandatory `memcmp` redirection was unavailable.
No successful Memcheck run is claimed. The Docker image pinned to Rust 1.57
was not built in this session; measurements use Rust 1.98.1 for both binaries.

## Reproduce

From the repository root, with Rust, Python 3 and SBCL 2.6.8 installed:

```sh
git worktree add --detach ../primes-rust-baseline c8fa14d3e67835258ddd15230b8be6b9d77d4c48
cd ../primes-rust-baseline/PrimeRust/solution_1
cargo build --release --locked
```

In the candidate checkout's `PrimeRust/solution_1` directory:

```sh
cargo test --release --locked
cargo test --locked unrolled
cargo build --release --locked
python3 benchmarks/compare.py \
  --original /absolute/path/to/primes-rust-baseline/PrimeRust/solution_1/target/release/prime-sieve-rust \
  --candidate target/release/prime-sieve-rust \
  --baseline-ref c8fa14d3e67835258ddd15230b8be6b9d77d4c48 \
  --lisp ../../PrimeLisp/solution_3 \
  --cpu 0 --seconds 5 --repeats 5 --output benchmarks/local.json
```

Use an allowed logical CPU and keep both Rust builds on the same machine,
compiler, flags and release profile. Set `--sbcl` if SBCL is not on `PATH`.
Keep target directories separate if `CARGO_TARGET_DIR` is set. The comparison
script records raw stdout/stderr, versions, binary and Lisp-source hashes,
candidate source hashes, CPU identity and commands in JSON.
