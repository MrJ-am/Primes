#!/usr/bin/env python3
"""Re-run the frozen campaign snapshots with the unchanged shared harness."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sbcl", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True,
                        help="New directory for validation logs and all measurements")
    parser.add_argument("--cpu", type=int, default=min(os.sched_getaffinity(0)))
    args = parser.parse_args()
    campaign = Path(__file__).resolve().parent
    common = campaign.parent
    expected = json.loads((campaign / "initial-source-sha256.json").read_text())
    for name in ("bench.lisp", "bootstrap.lisp", "run.sh"):
        actual = hashlib.sha256((common / name).read_bytes()).hexdigest()
        if actual != expected[name]:
            raise RuntimeError(f"The historical common harness has changed: {name}")
    with tempfile.TemporaryDirectory(prefix="primes-frozen-campaign-") as staging:
        command = [sys.executable, str(campaign / "compare-final.py"),
                   "--sbcl", str(args.sbcl.resolve()),
                   "--output", str(args.output.resolve()), "--cpu", str(args.cpu)]
        for role in ("baseline", "batch", "interactive"):
            target = Path(staging) / role
            shutil.copytree(campaign / "candidates" / role, target)
            for name in ("bench.lisp", "bootstrap.lisp", "run.sh"):
                shutil.copy2(common / name, target / name)
            (target / ".method").write_text(role + "\n")
            command.extend([f"--{role}", str(target)])
        subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
