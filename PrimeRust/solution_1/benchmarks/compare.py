#!/usr/bin/env python3
"""Compare an unchanged Rust binary, the candidate, and Common Lisp solution 3."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--baseline-ref", required=True)
    parser.add_argument("--lisp", required=True, type=Path)
    parser.add_argument("--sbcl", default="sbcl")
    parser.add_argument("--cpu", type=int, default=0)
    parser.add_argument("--seconds", type=int, default=5)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.seconds < 5 or args.repeats < 3:
        parser.error("use at least three samples of five seconds")
    os.sched_setaffinity(0, {args.cpu})
    rust_args = ["--bits-unrolled", "--threads", "1", "--seconds", str(args.seconds),
                 "--limit", "1000000"]
    commands = {
        "rust_original": [str(args.original.resolve()), *rust_args],
        "rust_candidate": [str(args.candidate.resolve()), *rust_args],
        "lisp": [str(args.lisp.resolve() / "run.sh"), "batch", str(args.seconds), "1"],
    }
    cpu = next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
               if line.startswith("model name"))
    report = {
        "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "cpu": cpu, "logical_cpu": args.cpu, "platform": platform.platform(),
        "limit": 1000000, "seconds": args.seconds, "repeats": args.repeats,
        "rustc": subprocess.check_output(["rustc", "--version"], text=True).strip(),
        "sbcl": subprocess.check_output([args.sbcl, "--version"], text=True).strip(),
        "binary_sha256": {"rust_original": digest(args.original),
                          "rust_candidate": digest(args.candidate)},
        "lisp_sha256": {p.name: digest(p) for p in sorted(args.lisp.glob("*.lisp"))},
        "commands": commands, "samples": [],
    }
    source = Path(__file__).resolve().parents[1]
    report["baseline_ref"] = args.baseline_ref
    report["candidate_source_commit"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    report["candidate_source_sha256"] = {
        name: digest(source / "prime-sieve-rust" / "src" / name)
        for name in ["main.rs", "unrolled.rs", "unrolled_extreme.rs"]
    }
    report["cargo_build_config"] = (source / ".cargo" / "config").read_text()
    env = dict(os.environ, SBCL=args.sbcl)
    names = list(commands)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for round_number in range(args.repeats):
        # Rotate positions and reverse alternate rounds to reduce order bias.
        order = names[round_number % 3:] + names[:round_number % 3]
        if round_number % 2:
            order.reverse()
        for name in order:
            run = subprocess.run(commands[name], env=env, text=True, capture_output=True,
                                 check=True, timeout=args.seconds + 180)
            lines = [line for line in run.stdout.splitlines() if line.count(";") == 4]
            if len(lines) != 1 or "Valid: Pass" not in run.stderr:
                raise RuntimeError(f"Invalid result for {name}: {run.stdout}\n{run.stderr}")
            label, passes, elapsed, threads, tags = lines[0].split(";")
            if threads != "1" or "faithful=yes" not in tags or "bits=1" not in tags:
                raise RuntimeError(f"Unexpected benchmark characteristics: {lines[0]}")
            rate = int(passes) / float(elapsed)
            report["samples"].append({"round": round_number + 1, "name": name,
                "label": label, "passes": int(passes), "elapsed": float(elapsed),
                "passes_per_second": rate, "tags": tags,
                "stdout": run.stdout, "stderr": run.stderr})
            args.output.write_text(json.dumps(report, indent=2) + "\n")
            print(f"{round_number + 1}/{args.repeats} {name}: {rate:.1f} passes/s", flush=True)
    report["summary"] = {}
    for name in names:
        rates = [s["passes_per_second"] for s in report["samples"] if s["name"] == name]
        report["summary"][name] = {"median": statistics.median(rates),
                                   "minimum": min(rates), "maximum": max(rates)}
    report["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report["summary"], indent=2))


if __name__ == "__main__":
    main()
