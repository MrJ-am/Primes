#!/usr/bin/env python3
"""Fresh-image alternating comparison; never compile concurrently with timing."""
import argparse, hashlib, json, os, re, shutil, statistics, subprocess, time
from pathlib import Path
campaign=Path(__file__).resolve().parent
root=campaign.parent
sbcl=os.environ.get('SBCL') or ((root/'.sbcl-path').read_text().strip() if (root/'.sbcl-path').exists() else 'sbcl')
cpu=os.environ.get('PRIMES_CPU',str(min(os.sched_getaffinity(0))))
base=['taskset','-c',cpu,sbcl,'--dynamic-space-size','1024','--noinform','--no-sysinit','--no-userinit','--non-interactive']
parser=argparse.ArgumentParser()
parser.add_argument('--output',default='final')
parser.add_argument('--cached',action='store_true')
parser.add_argument('--repeats',type=int,default=3)
args=parser.parse_args()
out=campaign/args.output
out.mkdir(exist_ok=True)
stages={}
# Copy each source once, so unchanged harness hashes identify the actual candidate.
for name,source in [('baseline',campaign/'baseline.lisp'),('selected',root/'sieve.lisp')]:
    stage=root/'.build/followup/comparison'/name
    stage.mkdir(parents=True,exist_ok=True)
    (stage/'results').mkdir(exist_ok=True)
    (stage/'.build').mkdir(exist_ok=True)
    if args.cached:
        assert (stage/'sieve.lisp').read_bytes()==source.read_bytes()
        for f in ['bench.lisp','bootstrap.lisp']:
            assert (stage/f).read_bytes()==(root/f).read_bytes()
        assert all((stage/'.build'/f'{n}.fasl').exists() for n in ['sieve','bench'])
        stages[name]=stage
        (out/f'{name}-source.sha256').write_text(hashlib.sha256(source.read_bytes()).hexdigest()+'\n')
        continue
    for f in ['bench.lisp','bootstrap.lisp']:
        shutil.copy2(root/f,stage/f)
    shutil.copy2(source,stage/'sieve.lisp')
    start=time.perf_counter()
    p=subprocess.run(base+['--load','bootstrap.lisp'],cwd=stage,capture_output=True,text=True)
    (out/f'{name}-compile.log').write_text(p.stdout+p.stderr)
    if p.returncode: raise RuntimeError(p.stderr[-2000:])
    stages[name]=stage
    (out/f'{name}-source.sha256').write_text(hashlib.sha256(source.read_bytes()).hexdigest()+'\n')
    print(json.dumps({'compile':name,'seconds':time.perf_counter()-start}),flush=True)
records=[]
order=[name for r in range(args.repeats) for name in (['baseline','selected'] if r%2==0 else ['selected','baseline'])]
for i,name in enumerate(order):
    stage=stages[name]
    env=dict(os.environ,PRIMES_CPU=cpu,PRIMES_MODE='batch',PRIMES_METHOD='followup-final-'+name)
    p=subprocess.run(base+['--load','.build/sieve.fasl','--load','.build/bench.fasl','--eval','(prime-bench:measure :seconds 5d0 :repeats 1)'],cwd=stage,env=env,capture_output=True,text=True)
    (out/f'{i+1:02d}-{name}.log').write_text(p.stdout+p.stderr)
    if p.returncode: raise RuntimeError(p.stderr[-2000:])
    raw=max((stage/'results').glob('*.sexp'),key=lambda f:f.stat().st_mtime_ns)
    shutil.copy2(raw,out/f'{i+1:02d}-{name}.sexp')
    s=raw.read_text()
    value=float(re.search(r':MICROSECONDS-PER-SIEVE\s+([\d.eEdD+-]+)',s).group(1).lower().replace('d','e'))
    records.append(dict(order=i+1,candidate=name,microseconds=value))
    print(json.dumps(records[-1]),flush=True)
summary={name:dict(median_us=statistics.median(r['microseconds'] for r in records if r['candidate']==name),samples=[r['microseconds'] for r in records if r['candidate']==name]) for name in stages}
summary['time_saved_percent']=100*(1-summary['selected']['median_us']/summary['baseline']['median_us'])
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary),flush=True)
