# C, Rust and Common Lisp: `wheel`

AMD EPYC 9V74, Linux x86-64, logical CPU 0 in a shared VM. Limit 1,000,000;
`faithful=yes,bits=1`; one thread. GCC 13.3.0, Rust 1.98.1, SBCL 2.6.8.
Reference repository: `58000dc01b4e572c490e0aaa59f4d6ba9955d73a`.

## Results

Passes per second; four five-second samples per entry. Entries run sequentially
in forward/reversed rotated order; compilation is outside the timed region.
The additional controls have three samples and were collected separately.

| Entry | Median | Min–max | Samples |
| --- | ---: | ---: | ---: |
| C 2, 5760/30030 wheel | 9,050 | 8,760–9,131 | 4 |
| C 7, sparse cofactor wheel | 13,308 | 12,908–13,597 | 4 |
| Lisp 2, wheel-opt | 4,246 | 3,940–4,431 | 4 |
| Lisp 5, sparse cofactor wheel | 19,401 | 19,194–19,918 | 4 |
| Rust 8, sparse cofactor wheel | 17,801 | 17,526–18,133 | 4 |
| Lisp 2, wheel-bitvector | 4,183 | 4,116–4,388 | 3 |

Relative to the explicitly named references: C: **+47.1%**, 4/4 paired rounds; Lisp: **+356.9%**, 4/4 paired rounds.

All candidates use a sparse modulo-30 cofactor wheel. Dense small-factor
marking and a 32 KiB cache traversal are retained. The new C port replaces runtime
mask/address work with constant carries and unrolled byte writes; Rust and Lisp
preserve the previously validated kernels after smaller/larger blocks failed to
improve them. Both existing Lisp wheel variants were measured: the bitvector
control ran in a separate three-round campaign, recorded below.

Lisp has the highest median among these candidates on this machine.

See [raw measurements](2026-09-16-results.json) for every output line, command,
binary fingerprint, source hashes and compiler versions. Results are local to
this machine and toolchain; VM scheduling contributes observable variation.
Fresh allocation/initialization is included in every pass. Validation and the
last allocation's release follow the final timestamp. Original Lisp references
compile on launch, outside their benchmark timers.

## Reproduce

Install the compiler versions above. The Lisp entry's Dockerfile documents
building SBCL 2.6.8 from the pinned source. The script builds and checks first,
then serializes measurements onto the selected CPU.

```sh
python3 benchmarks/wheel/compare.py --output /tmp/wheel-results.json --cpu 0 --repeats 4
```

`--sbcl /path/to/sbcl` selects the Lisp runtime. `--skip-build` reuses binaries.
The archived commands contain this run's absolute paths; `compare.py` reconstructs
paths relative to your checkout. Its default category-only order differs from
the original combined three-category campaign, whose exact order is archived.

## Validation and limits

New C entries: independent full flags, prime squares and storage boundaries,
10M count, ASan and UBSan. LeakSanitizer itself cannot run under this environment's
tracing, so address/undefined checks used `ASAN_OPTIONS=detect_leaks=0`.

Lisp candidates: independent full-flag oracle, native memory guards, state
lifetimes, boundary cases and the count of 664,579 primes through ten million.
New Rust entries: seven tests in optimized and debug builds, including independent full flags through 2,000,003 and the 10M count.

Native builds were tested. Dockerfiles were reviewed but Docker builds were not
run locally because Docker is unavailable. Upstream CI is a separate gate.

The experiment was developed with ChatGPT/Codex under human direction. Only
retained implementations contribute to the result table; exploratory settings
with inconsistent gains were discarded.
