#!/usr/bin/env python3
"""Time SBCL recovery or isolated experiments without copying source files."""
import json, os, subprocess, sys, time
from pathlib import Path
root=Path(__file__).resolve().parent.parent
os.chdir(root)
sbcl=os.environ.get('SBCL') or ((root/'.sbcl-path').read_text().strip() if (root/'.sbcl-path').exists() else 'sbcl')
label=sys.argv[1]
command=['taskset','-c','0',sbcl,'--dynamic-space-size','1024','--noinform','--no-sysinit','--no-userinit','--non-interactive',*sys.argv[2:]]
start=time.perf_counter()
try:
    p=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
except subprocess.TimeoutExpired as e:
    output=e.stdout or b''
    if isinstance(output,bytes): output=output.decode(errors='replace')
    p=subprocess.CompletedProcess(command,124,output+'\nStopped after the 120-second experiment timeout.\n')
elapsed=time.perf_counter()-start
(root/'campaign-2026-09-13-followup/diagnostics'/f'{label}.log').write_text(p.stdout)
record={'label':label,'wall_seconds':elapsed,'returncode':p.returncode,'command':command}
with (root/'campaign-2026-09-13-followup/process-costs.jsonl').open('a') as out:
    out.write(json.dumps(record)+'\n')
print(json.dumps({k:v for k,v in record.items() if k!='command'}))
if p.returncode: print(p.stdout[-6000:])
sys.exit(p.returncode)
