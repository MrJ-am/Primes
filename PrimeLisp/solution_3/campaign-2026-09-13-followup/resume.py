#!/usr/bin/env python3
"""Rebuild a versioned cache when needed, then reopen the reproducible Lisp image."""
import hashlib, json, os, subprocess, sys, time
from pathlib import Path
campaign=Path(__file__).resolve().parent
root=campaign.parent
os.chdir(root)
sbcl=os.environ.get('SBCL') or ((root/'.sbcl-path').read_text().strip() if (root/'.sbcl-path').exists() else 'sbcl')
cpu=os.environ.get('PRIMES_CPU',str(min(os.sched_getaffinity(0))))
version=subprocess.check_output([sbcl,'--version'])
fingerprint=hashlib.sha256(version+(root/'sieve.lisp').read_bytes()+(root/'bench.lisp').read_bytes()).hexdigest()
cache=root/'.build/followup'/fingerprint
base=['taskset','-c',cpu,sbcl,'--dynamic-space-size','1024','--noinform','--no-sysinit','--no-userinit']
if not all((cache/f'{n}.fasl').exists() for n in ['sieve','bench']):
    cache.mkdir(parents=True,exist_ok=True)
    code='(declaim (sb-ext:muffle-conditions sb-ext:compiler-note))\n'
    for name in ['sieve','bench']:
        code+=f'(multiple-value-bind (f w failed) (compile-file "{name}.lisp" :output-file "{cache/name}.fasl" :verbose nil :print nil) (declare (ignore w)) (assert (not failed)) (load f))\n'
    builder=cache/'build.lisp'
    builder.write_text(code)
    start=time.perf_counter()
    p=subprocess.run(base+['--non-interactive','--load',str(builder)],capture_output=True,text=True)
    (cache/'build.log').write_text(p.stdout+p.stderr)
    if p.returncode: sys.exit(p.stdout+p.stderr)
    print(f'Cache compiled and loaded in {time.perf_counter()-start:.3f}s.',flush=True)
os.environ.update(PRIMES_CPU=cpu,PRIMES_MODE='repl',PRIMES_METHOD='interactive-followup')
command=base+(['--non-interactive'] if '--check' in sys.argv else [])
command+=['--load',str(cache/'sieve.fasl'),'--load',str(cache/'bench.fasl'),'--load',str(campaign/'lab.lisp'),'--eval','(lab:restore)']
os.execvp(command[0],command)
