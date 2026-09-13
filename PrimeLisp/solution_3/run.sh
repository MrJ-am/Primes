#!/bin/sh
set -eu
cd -- "$(dirname -- "$0")"

task_sbcl=${SBCL:-}
if [ -z "$task_sbcl" ] && [ -f .sbcl-path ]; then
    IFS= read -r task_sbcl < .sbcl-path
fi
task_sbcl=${task_sbcl:-sbcl}

PRIMES_MODE=${1:-batch}
case "$PRIMES_MODE" in
    batch|repl|check) ;;
    *) echo 'Usage: ./run.sh [batch|repl|check] [seconds=5] [repeats=3]' >&2; exit 2 ;;
esac
PRIMES_SECONDS=${2:-5}
PRIMES_REPEATS=${3:-3}
PRIMES_CPU=${PRIMES_CPU:-$(python3 -c 'import os; print(min(os.sched_getaffinity(0)))')}
PRIMES_METHOD=${PRIMES_METHOD:-baseline}
if [ -f .method ]; then IFS= read -r PRIMES_METHOD < .method; fi
export PRIMES_MODE PRIMES_SECONDS PRIMES_REPEATS PRIMES_CPU PRIMES_METHOD

set -- --dynamic-space-size 1024 --noinform --no-sysinit --no-userinit
if [ "$PRIMES_MODE" = repl ]; then
    exec taskset -c "$PRIMES_CPU" "$task_sbcl" "$@" --load bootstrap.lisp
else
    exec taskset -c "$PRIMES_CPU" "$task_sbcl" "$@" --non-interactive \
        --load bootstrap.lisp --eval '(prime-bench:main)'
fi
