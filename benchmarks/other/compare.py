#!/usr/bin/env python3
"""Build and compare faithful, single-thread, one-bit sieves in one category."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[2]
CATEGORY = Path(__file__).resolve().parent.name


def run(command, cwd):
    subprocess.run(list(map(str, command)), cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reference', type=Path, help='Unmodified upstream worktree (required for other)')
    parser.add_argument('--sbcl', default=os.environ.get('SBCL', 'sbcl'))
    parser.add_argument('--cpu', type=int, default=0)
    parser.add_argument('--repeats', type=int, default=4)
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    if args.repeats < 3:
        parser.error('Use at least three repetitions.')
    if CATEGORY == 'other' and not args.reference:
        parser.error('Pass --reference pointing to upstream commit 58000dc01b4e572c490e0aaa59f4d6ba9955d73a.')
    reference = args.reference.resolve() if args.reference else ROOT
    sbcl = shutil.which(args.sbcl)
    if not sbcl:
        parser.error('SBCL 2.6.8 is required.')
    os.environ['SBCL'] = sbcl
    c_num = {'base': 6, 'wheel': 7}.get(CATEGORY)
    l_num = {'base': 4, 'wheel': 5, 'other': 3}[CATEGORY]
    r_num = {'base': 1, 'wheel': 8, 'other': 9}[CATEGORY]
    lisp = ROOT / f'PrimeLisp/solution_{l_num}'
    rust = ROOT / f'PrimeRust/solution_{r_num}'
    c_five = reference / 'PrimeC/solution_5'
    c_two = ROOT / 'PrimeC/solution_2'
    entries = []

    def add(name, command, cwd=ROOT):
        entries.append({'name': name, 'command': list(map(str, command)), 'cwd': str(cwd)})

    if not args.skip_build:
        run(['./run.sh', 'check'], lisp)
        if c_num:
            run(['./run.sh', 'check'], ROOT / f'PrimeC/solution_{c_num}')
        if CATEGORY == 'base':
            run(['cargo', 'build', '--release', '--locked', '--target-dir', rust / 'target'], rust)
            run(['./sieve', 'sieve_base', 'compile', 'gcc', '--verbose', '0'], c_five)
        else:
            run(['./run.sh', 'check'], rust)
            run(['rustc', '--edition=2021', '-O', '-C', 'target-cpu=native', '-C', 'target-feature=-avx512f', 'main.rs', '-o', 'sieve'], rust)
        if CATEGORY == 'wheel':
            run(['gcc', '-Ofast', '-march=native', '-mno-avx512f', '-mtune=native', '-funroll-all-loops', 'sieve_5760of30030_only_write_read_bits.c', '-lm', '-o', 'sieve_5760of30030_only_write_read_bits'], c_two)
        if CATEGORY == 'other':
            run(['./check_sparse.sh'], ROOT / 'PrimeC/solution_5')
            for directory in [c_five, ROOT / 'PrimeC/solution_5']:
                run(['./sieve', 'sieve_extend', 'compile', 'gcc', '--verbose', '0'], directory)

    if CATEGORY == 'base':
        add('c-base-reference', [c_five / 'bin/sieve_base', '--time', '5'])
        add('c-base-candidate', [ROOT / 'PrimeC/solution_6/sieve'], ROOT / 'PrimeC/solution_6')
        add('lisp-base-reference', [sbcl, '--script', 'PrimeSievebitops.lisp'], ROOT / 'PrimeLisp/solution_2')
        add('lisp-base-candidate', [lisp / 'run.sh', 'batch', '5'])
        for mode in ['unrolled', 'extreme']:
            add('rust-base-' + mode, [rust / 'target/release/prime-sieve-rust', '--bits-' + mode, '--threads', '1', '--seconds', '5'])
    elif CATEGORY == 'wheel':
        add('c-wheel-reference', [c_two / 'sieve_5760of30030_only_write_read_bits'])
        add('c-wheel-candidate', [ROOT / 'PrimeC/solution_7/sieve'], ROOT / 'PrimeC/solution_7')
        for mode, file in [('reference', 'PrimeSieveWheelOpt.lisp'), ('bitvector-reference', 'PrimeSieveWheelBitvector.lisp')]:
            add('lisp-wheel-' + mode, [sbcl, '--script', file], ROOT / 'PrimeLisp/solution_2')
        add('lisp-wheel-candidate', [lisp / 'run.sh', 'batch', '5'])
        add('rust-wheel-candidate', [rust / 'sieve'])
    else:
        fixed = ['--tune', '0', '--time', '5', '--set', 's064-l128-b0262144-v256-a1']
        for name, directory in [('reference', c_five), ('candidate', ROOT / 'PrimeC/solution_5')]:
            add('c-other-' + name, [directory / 'bin/sieve_extend', *fixed])
            add('c-other-default-' + name, [directory / 'bin/sieve_extend', '--time', '5'])
        add('lisp-other-reference', [sbcl, '--script', 'PrimeSievewordops.lisp'], ROOT / 'PrimeLisp/solution_2')
        add('lisp-other-candidate', [lisp / 'run.sh', 'batch', '5'])
        add('rust-other-candidate', [rust / 'sieve'])

    os.sched_setaffinity(0, {args.cpu})
    report = {'category': CATEGORY, 'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'cpu': next(line for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')),
              'logical_cpu': args.cpu, 'platform': platform.platform(), 'limit': 1000000,
              'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'tool_versions': {tool: subprocess.check_output([program, '--version'], text=True).splitlines()[0]
                                for tool, program in [('gcc', 'gcc'), ('rustc', 'rustc'), ('sbcl', sbcl)]},
              'reference_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=reference, text=True).strip(),
              'entries': entries, 'samples': []}
    for e in entries:
        e['executable_sha256'] = hashlib.sha256(Path(e['command'][0]).read_bytes()).hexdigest()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    for repetition in range(args.repeats):
        offset = (repetition // 2) % len(entries)
        order = entries[offset:] + entries[:offset]
        if repetition % 2:
            order.reverse()
        for e in order:
            result = subprocess.run(e['command'], cwd=e['cwd'], text=True, capture_output=True, check=True, timeout=240)
            rows = [line for line in result.stdout.splitlines() if ';' in line and 'algorithm=' in line]
            if len(rows) != 1:
                raise RuntimeError(f"Unexpected output for {e['name']}: {result.stdout}\n{result.stderr}")
            label, passes, seconds, threads, tags, *_ = rows[0].split(';')
            tag_map = dict(t.split('=') for t in tags.split(','))
            assert threads == '1' and tag_map == {'algorithm': CATEGORY, 'faithful': 'yes', 'bits': '1'}
            assert int(passes) > 0 and float(seconds) >= 5.0
            rate = int(passes) / float(seconds)
            report['samples'].append({'round': repetition + 1, 'name': e['name'], 'label': label,
                                      'passes': int(passes), 'seconds': float(seconds), 'pps': rate,
                                      'stdout': result.stdout, 'stderr': result.stderr, 'tags': tags})
            args.output.write_text(json.dumps(report, indent=2) + '\n')
            print(f"{repetition+1}/{args.repeats} {e['name']}: {rate:.1f} passes/s", flush=True)
    report['summary'] = {}
    for e in entries:
        rates = [s['pps'] for s in report['samples'] if s['name'] == e['name']]
        report['summary'][e['name']] = {'median': statistics.median(rates), 'min': min(rates), 'max': max(rates)}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['summary'], indent=2))


if __name__ == '__main__':
    main()
