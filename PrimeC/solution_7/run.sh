#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
cc=${CC:-gcc}
"$cc" -O3 -march=native -mno-avx512f -Wall -Wextra sieve.c -o sieve
exec ./sieve "$@"
