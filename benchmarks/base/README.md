# C, Rust and Common Lisp: `base`

AMD EPYC 9V74, Linux x86-64, logical CPU 0 in a shared VM. Limit 1,000,000;
`faithful=yes,bits=1`; one thread. GCC 13.3.0, Rust 1.98.1, SBCL 2.6.8.
Reference repository: `58000dc01b4e572c490e0aaa59f4d6ba9955d73a`.

## Results

Passes per second; four five-second samples per entry. Entries run sequentially
in forward/reversed rotated order; compilation is outside the timed region.
The additional controls have three samples and were collected separately.

| Entry | Median | Min–max | Samples |
| --- | ---: | ---: | ---: |
| C 5, original base | 4,041 | 4,027–4,057 | 4 |
| C 6, new base | 13,815 | 12,894–14,104 | 4 |
| Lisp 2, dense | 3,331 | 3,251–3,422 | 4 |
| Lisp 4, native base | 10,139 | 9,405–10,364 | 4 |
| Rust 1, original unrolled | 14,219 | 13,462–14,509 | 4 |
| Rust 1, original extreme | 14,147 | 13,960–14,465 | 4 |

Relative to the explicitly named references: C: **+241.9%**, 4/4 paired rounds; Lisp: **+204.4%**, 4/4 paired rounds.

The C and Lisp entries transfer the dense/sparse strategy from Rust solution 1.
The Lisp generator uses single-assignment `let*` bindings so unmodified SBCL can
fold consecutive single-bit operations. Both new entries switch to byte kernels
above factor 63. Rust's original unrolled and extreme implementations are retained:
stride decomposition, a different factor scan, sparse inlining changes, denser
unrolling and lower cutoffs did not establish a repeatable improvement.

Rust has the highest median here, but its lead over C is small relative to the
observed spread. This is not evidence of a universal language ranking.

See [raw measurements](2026-09-16-results.json) for every output line, command,
binary fingerprint, source hashes and compiler versions. Results are local to
this machine and toolchain; VM scheduling contributes observable variation.
Fresh allocation/initialization is included in every pass. Validation and the
last allocation's release follow the final timestamp. The C solution 5 reference
uses its own untimed warmup and default automatic tuning.

## Reproduce

Install the compiler versions above. The Lisp entry's Dockerfile documents
building SBCL 2.6.8 from the pinned source. The script builds and checks first,
then serializes measurements onto the selected CPU.

```sh
python3 benchmarks/base/compare.py --output /tmp/base-results.json --cpu 0 --repeats 4
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
Rust solution 1 is unmodified; each timed sample validates its final sieve.

Native builds were tested. Dockerfiles were reviewed but Docker builds were not
run locally because Docker is unavailable. Upstream CI is a separate gate.

The experiment was developed with ChatGPT/Codex under human direction. Only
retained implementations contribute to the result table; exploratory settings
with inconsistent gains were discarded.
