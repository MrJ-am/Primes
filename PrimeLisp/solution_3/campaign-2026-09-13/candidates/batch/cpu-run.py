#!/usr/bin/env python3
"""Serialize fresh SBCL jobs and record only the actual lock-acquisition wait."""
import datetime, fcntl, json, os, pathlib, subprocess, sys, time
label, *command = sys.argv[1:]
root = pathlib.Path(__file__).resolve().parent
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with open('/tmp/primes-campaign-cpu.lock', 'a') as lock:
    before = time.monotonic()
    fcntl.flock(lock, fcntl.LOCK_EX)
    waited = time.monotonic() - before
    print(f'{label}: acquired CPU lock after {waited:.6f} seconds', flush=True)
    env = os.environ.copy()
    env['PRIMES_CPU'] = '0'
    os.sched_setaffinity(0, {0})
    run_start = time.monotonic()
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    (root / 'diagnostics' / f'{label}.log').write_bytes(result.stdout)
    duration = time.monotonic() - run_start
    fcntl.flock(lock, fcntl.LOCK_UN)
record = dict(label=label, started_utc=started, waited_seconds=waited,
              run_seconds=duration, command=command, returncode=result.returncode)
with open(root / 'diagnostics' / 'cpu-lock.jsonl', 'a') as output:
    output.write(json.dumps(record) + '\n')
print(json.dumps(record), flush=True)
print(''.join((root / 'diagnostics' / f'{label}.log').read_text().splitlines(keepends=True)[-35:]), end='')
sys.exit(result.returncode)
