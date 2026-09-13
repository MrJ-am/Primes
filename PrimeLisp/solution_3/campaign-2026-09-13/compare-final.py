#!/usr/bin/env python3
"""Verify frozen candidates and compare them in alternating fresh SBCL images."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


def git_head(root):
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                            capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def main():
    parser = argparse.ArgumentParser()
    for role in ("baseline", "batch", "interactive"):
        parser.add_argument(f"--{role}", type=Path, required=True,
                            help="Path to this checkout's PrimeLisp/solution_3")
    parser.add_argument("--sbcl", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cpu", type=int, default=0)
    args = parser.parse_args()
    roots = {r: getattr(args, r).resolve() for r in ("baseline", "batch", "interactive")}
    scripts = Path(__file__).resolve().parent
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for name in ("bench.lisp", "bootstrap.lisp", "run.sh"):
        expected = (roots["baseline"] / name).read_bytes()
        for role, root in roots.items():
            if (root / name).read_bytes() != expected:
                raise RuntimeError(f"Common harness changed: {role}/{name}")

    env = os.environ.copy()
    env.update(SBCL=str(args.sbcl.resolve()), PRIMES_CPU=str(args.cpu),
               PRIMES_BENCH_LOCK="/tmp/primes-common-lisp-benchmark.lock")
    # Hold the CPU gate for the whole final check. Both developers must be frozen.
    with open("/tmp/primes-campaign-cpu.lock", "a+") as gate:
        fcntl.flock(gate, fcntl.LOCK_EX)
        for role in ("batch", "interactive"):
            command = ["taskset", "-c", str(args.cpu), str(args.sbcl.resolve()),
                       "--dynamic-space-size", "1024", "--noinform", "--no-sysinit",
                       "--no-userinit", "--non-interactive", "--load", "bootstrap.lisp",
                       "--load", str(scripts / "verify-final.lisp")]
            completed = subprocess.run(command, cwd=roots[role], env=env,
                                       capture_output=True, text=True, timeout=90)
            (output / f"validation-{role}.log").write_text(completed.stdout + completed.stderr)
            if completed.returncode:
                raise RuntimeError(f"Independent validation failed for {role}; see log")
            print(f"{role}: independent validation passed", flush=True)

        records = []
        order = ["baseline", "batch", "interactive", "interactive", "baseline",
                 "batch", "batch", "interactive", "baseline"]
        for index, role in enumerate(order, 1):
            root = roots[role]
            before = set((root / "results").glob("*.sexp"))
            started = time.time()
            completed = subprocess.run(["./run.sh", "batch", "5", "1"], cwd=root,
                                       env=env, capture_output=True, text=True, timeout=90)
            (output / f"sample-{index:02d}-{role}.log").write_text(
                completed.stdout + completed.stderr)
            if completed.returncode:
                raise RuntimeError(f"Measurement failed for {role}; see log")
            new_logs = set((root / "results").glob("*.sexp")) - before
            if len(new_logs) != 1:
                raise RuntimeError(f"Expected one new result record, got {new_logs}")
            source = new_logs.pop()
            archived = output / f"sample-{index:02d}-{role}.sexp"
            archived.write_bytes(source.read_bytes())
            exported = subprocess.check_output(
                [str(args.sbcl.resolve()), "--noinform", "--no-sysinit", "--no-userinit",
                 "--script", str(scripts / "read-results.lisp"), str(archived)], text=True)
            fields = exported.strip().split("|")
            if len(fields) != 16:
                raise RuntimeError(f"Unexpected exported record: {exported}")
            number = lambda x: float(x.replace("d", "e").replace("D", "e"))
            records.append({
                "order": index, "role": role, "started_unix": started,
                "log": archived.name, "label": fields[4], "sbcl": fields[5],
                "cpu": fields[6], "tags": fields[7], "passes": int(fields[9]),
                "seconds": number(fields[10]), "microseconds_per_sieve": number(fields[11]),
                "sieves_per_second": number(fields[12]), "cpu_seconds": number(fields[13]),
                "bytes_consed": int(fields[14]), "gc_seconds": number(fields[15]),
                "sieve_sha256": hashlib.sha256((root / "sieve.lisp").read_bytes()).hexdigest(),
                "commit": git_head(root),
            })
            print(f"{index}/9 {role}: {records[-1]['microseconds_per_sieve']:.3f} us/sieve",
                  flush=True)
        summary = {}
        for role in roots:
            samples = [x["microseconds_per_sieve"] for x in records if x["role"] == role]
            median = statistics.median(samples)
            summary[role] = {"median_microseconds_per_sieve": median,
                             "median_derived_sieves_per_second": 1e6 / median,
                             "min_microseconds": min(samples), "max_microseconds": max(samples)}
        baseline = summary["baseline"]["median_microseconds_per_sieve"]
        for role in ("batch", "interactive"):
            median = summary[role]["median_microseconds_per_sieve"]
            summary[role].update(speedup_vs_baseline=baseline / median,
                                 time_saved_fraction=1 - median / baseline)
        (output / "results.json").write_text(json.dumps(
            {"order": order, "samples": records, "summary": summary}, indent=2) + "\n")
        print(json.dumps(summary, indent=2), flush=True)


if __name__ == "__main__":
    main()
