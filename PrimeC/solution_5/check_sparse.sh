#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"
mkdir -p dev/build
${CC:-gcc} -O2 -march=native -DCOMPILE_VERBOSE_LEVEL=0 check_sparse.c -o dev/build/check_sparse
exec dev/build/check_sparse
