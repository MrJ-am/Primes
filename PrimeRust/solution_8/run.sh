#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
if [ "${1:-}" = check ]; then
    rustc --edition=2021 --test -O -C target-cpu=native -C target-feature=-avx512f main.rs -o sieve-check
    exec ./sieve-check
fi
rustc --edition=2021 -O -C target-cpu=native -C target-feature=-avx512f main.rs -o sieve
exec ./sieve "$@"
