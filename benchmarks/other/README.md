# C, Rust and Common Lisp: `other`

AMD EPYC 9V74, Linux x86-64, logical CPU 0 in a shared VM. Limit 1,000,000;
`faithful=yes,bits=1`; one thread. GCC 13.3.0, Rust 1.98.1, SBCL 2.6.8.
Reference repository: `58000dc01b4e572c490e0aaa59f4d6ba9955d73a`.

## Results

Passes per second; four five-second samples per entry. Entries run sequentially
in forward/reversed rotated order; compilation is outside the timed region.
The additional controls have three samples and were collected separately.

| Entry | Median | Min–max | Samples |
| --- | ---: | ---: | ---: |
| C 5, original, fixed parameters | 16,757 | 16,389–16,857 | 4 |
| C 5, sparse periods, fixed parameters | 18,156 | 17,884–18,759 | 4 |
| Lisp 2, word operations | 2,958 | 2,920–2,968 | 4 |
| Lisp 3, existing PR kernel | 15,905 | 15,206–16,215 | 4 |
| Rust 9, blocked dense/sparse | 16,229 | 15,931–16,726 | 4 |
| C 5, original, automatic tuning | 17,413 | 17,291–18,052 | 3 |
| C 5, sparse periods, automatic tuning | 18,004 | 16,807–18,139 | 3 |

Relative to the explicitly named references: C: **+8.4%**, 4/4 paired rounds; Lisp: **+437.7%**, 4/4 paired rounds.

C retains its runtime pattern-extension algorithm and substitutes eight-write
sparse periods above factor 129. Rust uses dense/sparse marking in 32 KiB blocks;
its changed global traversal is conservatively classified as `other`. Lisp retains
the original PR #1082 kernel, with explicit AVX2 multi-composite masks. These are
comparisons within the project's category, not identical algorithms.

The C kernel improves at identical fixed parameters in every paired round.
Default automatic tuning was also checked separately. Its samples overlap and
the candidate wins only one of three paired rounds: the default-mode result is
inconclusive, despite its higher median. The fixed-parameter gain must not be read
as a guaranteed improvement from the automatic tuner on every machine.

C has the highest median in this category. Smaller blocks and wider sparse
unrolling were rejected for Lisp; the original PR's Lisp implementation is retained.
The Lisp reference below is upstream solution 2, not the earlier version of PR #1082.

See [raw measurements](2026-09-16-results.json) for every output line, command,
binary fingerprint, source hashes and compiler versions. Results are local to
this machine and toolchain; VM scheduling contributes observable variation.
Fresh allocation/initialization is included in every pass. Validation and the
last allocation's release follow the final timestamp. C solution 5 has its own
untimed warmup and, when enabled, automatic tuning. In the fixed comparison both
C binaries use `--tune 0 --set s064-l128-b0262144-v256-a1`.

## Reproduce

Install the compiler versions above. The Lisp entry's Dockerfile documents
building SBCL 2.6.8 from the pinned source. The script builds and checks first,
then serializes measurements onto the selected CPU.

For the `other` category, first create an unmodified worktree for C solution 5:

```sh
git worktree add --detach /tmp/primes-reference 58000dc01b4e572c490e0aaa59f4d6ba9955d73a
```

```sh
python3 benchmarks/other/compare.py --output /tmp/other-results.json --cpu 0 --repeats 4 --reference /tmp/primes-reference
```

`--sbcl /path/to/sbcl` selects the Lisp runtime. `--skip-build` reuses binaries.
The archived commands contain this run's absolute paths; `compare.py` reconstructs
paths relative to your checkout. Its default category-only order differs from
the original combined three-category campaign, whose exact order is archived.

## Validation and limits

C extension: every odd flag against an independent byte sieve, both extension
algorithms, three block sizes and limits through ten million (`check_sparse.sh`).

Lisp candidates: independent full-flag oracle, native memory guards, state
lifetimes, boundary cases and the count of 664,579 primes through ten million.
New Rust entries: seven tests in optimized and debug builds, including independent full flags through 2,000,003 and the 10M count.

Native builds were tested. Dockerfiles were reviewed but Docker builds were not
run locally because Docker is unavailable. Upstream CI is a separate gate.

The experiment was developed with ChatGPT/Codex under human direction. Only
retained implementations contribute to the result table; exploratory settings
with inconsistent gains were discarded.
