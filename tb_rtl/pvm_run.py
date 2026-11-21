#!/usr/bin/env python3
"""PVM evidence runner (house-method semantics, Icarus Verilog backend).

The only way an RTL simulation result counts in PVM (spec/09_HOUSE_METHOD.md sec. 6, adapted).
Registry: tb_rtl/pvm_jobs.json. Expected check counts are frozen there BEFORE the first run.

Usage (from repo root):
  python tb_rtl/pvm_run.py selftest            # judge self-tests; run before ANY registry change
  python tb_rtl/pvm_run.py list
  python tb_rtl/pvm_run.py run --select S01    # a stage selection, or a single job id
  python tb_rtl/pvm_run.py run --select all

States written to evidence/<job>/result.json:
  PASS_FRESH      positive job: RESULT : PASS, CHECKS == frozen, ERRORS == 0, no [FAIL], no timeout
  NEG_KILLED      negative/mutant job: ran all frozen checks, RESULT : FAIL, every targeted check failed,
                  no unrelated [FAIL]  (this is the PASS state for a negative job)
  FAIL / NEG_SURVIVED / NEG_UNRELATED / COUNT_MISMATCH / TIMEOUT / COMPILE_FAIL / MUTANT_ANCHOR_ERROR
Retries: none. A timeout is never a pass or a kill. Old evidence is never relabelled: each run writes a new
timestamped record and updates latest.json.
"""
import argparse, datetime, hashlib, json, os, re, shutil, subprocess, sys
import pvm_trace_jobs

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
REG = os.path.join(ROOT, 'tb_rtl', 'pvm_jobs.json')
EVID = os.path.join(ROOT, 'evidence')
def sha(p):
    with open(p, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def parse(log):
    passes = re.findall(r'^\[PASS\]\s+(\S+)', log, re.M)
    fails = re.findall(r'^\[FAIL\]\s+(\S+)', log, re.M)
    m = re.search(r'^CHECKS\s*:\s*(\d+)', log, re.M); checks = int(m.group(1)) if m else None
    m = re.search(r'^ERRORS\s*:\s*(\d+)', log, re.M); errors = int(m.group(1)) if m else None
    m = re.search(r'^RESULT\s*:\s*(PASS|FAIL)', log, re.M); result = m.group(1) if m else None
    timeout = bool(re.search(r'^TB_TIMEOUT', log, re.M))
    return dict(passes=passes, fails=fails, checks=checks, errors=errors, result=result, timeout=timeout)


def judge(job, p):
    frozen = job['checks']
    if p['timeout'] or p['result'] is None:
        return 'TIMEOUT'
    if p['checks'] != frozen or len(p['passes']) + len(p['fails']) != frozen:
        return 'COUNT_MISMATCH'
    if not job.get('negative'):
        ok = p['result'] == 'PASS' and p['errors'] == 0 and not p['fails']
        return 'PASS_FRESH' if ok else 'FAIL'
    targets = set(job['expect_fail_checks'])
    fails = set(p['fails'])
    if p['result'] != 'FAIL' or not targets.issubset(fails):
        return 'NEG_SURVIVED'
    if fails - targets:
        return 'NEG_UNRELATED'
    return 'NEG_KILLED'


def apply_mutant(text, anchor, replace):
    n = text.count(anchor)
    if n != 1:
        raise ValueError(f'anchor matched {n} times: {anchor[:60]!r}')
    return text.replace(anchor, replace)


def resolve_job(job, reg):
    if 'trace_of' not in job:
        return job
    bench = next(source for source in reg['jobs'] if source['id'] == job['trace_of'])
    return {**bench, **job, 'bench_checks': bench['checks']}


def run_job(job, root=ROOT, capture_trace=False):
    jid = job['id']; bdir = os.path.join(root, 'tb_rtl', 'build', jid)
    if os.path.isdir(bdir): shutil.rmtree(bdir)
    os.makedirs(bdir)
    srcs = [os.path.join(root, s) for s in job['sources']]
    names = [os.path.basename(s) for s in srcs]
    if len(set(names)) != len(names):
        return 'COMPILE_FAIL', {'error': 'duplicate source file name in list'}, ''
    mut = job.get('mutant')
    if mut:
        target = os.path.join(root, mut['file'])
        try:
            source = open(target).read()
            if 'delay_output' in mut:
                txt = pvm_trace_jobs.delay_output(source, mut['delay_output'], apply_mutant)
            else:
                txt = apply_mutant(source, mut['anchor'], mut['replace'])
        except ValueError as e:
            return 'MUTANT_ANCHOR_ERROR', {'error': str(e)}, ''
        mpath = os.path.join(bdir, os.path.basename(target))
        open(mpath, 'w').write(txt)
        srcs = [mpath if os.path.abspath(s) == os.path.abspath(target) else s for s in srcs]
    vvp = os.path.join(bdir, 'sim.vvp')
    cmd = ['iverilog', '-g2005', '-Wall', '-s', job['top'], '-o', vvp] + \
          [f'-D{d}' for d in job.get('defines', [])] + [f'-I{os.path.join(root, i)}' for i in job.get('include_dirs', [])] + srcs
    c = subprocess.run(cmd, capture_output=True, text=True)
    if c.returncode != 0:
        return 'COMPILE_FAIL', {'cmd': ' '.join(cmd)}, c.stdout + c.stderr
    try:
        trace_job = 'trace_of' in job
        args = ['+TRACE'] if trace_job else []
        r = subprocess.run(['vvp', '-n', vvp, *args], cwd=bdir if trace_job else None,
                           capture_output=True, text=True, timeout=job.get('sim_timeout', 600))
        log = c.stdout + c.stderr + r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        return 'TIMEOUT', {'cmd': ' '.join(cmd)}, str(e)
    p = parse(log)
    if trace_job:
        if (r.returncode or p['timeout'] or p['checks'] != job['bench_checks'] or
                (not job.get('negative') and p['result'] != 'PASS') or p['result'] is None):
            return 'TRACE_BENCH_FAIL', dict(parsed=p, cmd=' '.join(cmd)), log
        trace = os.path.join(bdir, 'trace.csv')
        if capture_trace:
            return 'PASS_FRESH', {'trace': trace}, log
        try:
            detail, trace_result = pvm_trace_jobs.compare(root, job, trace)
        except (OSError, ValueError, KeyError) as e:
            return 'TRACE_INPUT_ERROR', {'error': str(e)}, log + f'\nTRACE_INPUT_ERROR {e}\n'
        log = '\n'.join(f'TB: {line}' for line in log.splitlines()) + '\n' + detail
        p = parse(log)
        return judge(job, p), dict(parsed=p, cmd=' '.join(cmd), trace=trace_result), log
    return judge(job, p), dict(parsed=p, cmd=' '.join(cmd)), log


def cmd_run(sel):
    reg = json.load(open(REG))
    jobs = [j for j in reg['jobs'] if sel == 'all' or j['selection'] == sel or j['id'] == sel]
    if not jobs:
        print(f'no jobs for selection {sel}'); return 2
    iv = subprocess.run(['iverilog', '-V'], capture_output=True, text=True).stdout.splitlines()[0]
    bad = 0
    for j in jobs:
        j = resolve_job(j, reg)
        state, info, log = run_job(j)
        inputs = j['sources'] + (['tb_rtl/pvm_trace_jobs.py', 'tb_rtl/pvm_run.py'] if 'trace_of' in j else [])
        ts = datetime.datetime.now().strftime('%Y%m%dT%H%M%S')
        d = os.path.join(EVID, j['id']); os.makedirs(d, exist_ok=True)
        rec = dict(id=j['id'], state=state, selection=j['selection'], frozen_checks=j['checks'],
                   checks_basis=j['checks_basis'], negative=bool(j.get('negative')), variant_of=j.get('variant_of'),
                   tool=iv, date=ts, sources={s: sha(os.path.join(ROOT, s)) for s in inputs}, **info)
        open(os.path.join(d, f'{ts}.log'), 'w').write(log)
        open(os.path.join(d, f'{ts}.json'), 'w').write(json.dumps(rec, indent=1))
        open(os.path.join(d, 'latest.json'), 'w').write(json.dumps(rec, indent=1))
        good = state in ('PASS_FRESH', 'NEG_KILLED')
        bad += not good
        print(f'{state:16s} {j["id"]}  (evidence/{j["id"]}/{ts}.log)')
    print(f'SUMMARY selection={sel} jobs={len(jobs)} accepted={len(jobs)-bad} rejected={bad}')
    return 1 if bad else 0


def cmd_selftest():
    job = dict(id='t', checks=3, checks_basis='', selection='x')
    L = lambda body: body
    cases = [
        (job, '[PASS] a\n[PASS] b\n[PASS] c\nCHECKS : 3\nERRORS : 0\nRESULT : PASS\n', 'PASS_FRESH'),
        (job, '[PASS] a\n[PASS] b\nCHECKS : 2\nERRORS : 0\nRESULT : PASS\n', 'COUNT_MISMATCH'),
        (job, '[PASS] a\n[FAIL] b\n[PASS] c\nCHECKS : 3\nERRORS : 1\nRESULT : FAIL\n', 'FAIL'),
        (job, '[PASS] a\nTB_TIMEOUT x\nRESULT : FAIL\n', 'TIMEOUT'),
        (job, '[PASS] a\n[PASS] b\n', 'TIMEOUT'),
        (dict(job, negative=True, expect_fail_checks=['b']), '[PASS] a\n[FAIL] b\n[PASS] c\nCHECKS : 3\nERRORS : 1\nRESULT : FAIL\n', 'NEG_KILLED'),
        (dict(job, negative=True, expect_fail_checks=['b']), '[PASS] a\n[FAIL] b\n[FAIL] c\nCHECKS : 3\nERRORS : 2\nRESULT : FAIL\n', 'NEG_UNRELATED'),
        (dict(job, negative=True, expect_fail_checks=['b']), '[PASS] a\n[PASS] b\n[PASS] c\nCHECKS : 3\nERRORS : 0\nRESULT : PASS\n', 'NEG_SURVIVED'),
        (dict(job, negative=True, expect_fail_checks=['b']), '[FAIL] b\nTB_TIMEOUT\nRESULT : FAIL\n', 'TIMEOUT'),
    ]
    ok = 0
    for i, (j, log, want) in enumerate(cases):
        got = judge(j, parse(L(log)))
        print(f'[{"PASS" if got == want else "FAIL"}] judge_case_{i} want={want} got={got}'); ok += got == want
    try:
        apply_mutant('a b a', 'a', 'x'); print('[FAIL] anchor_twice_rejected')
    except ValueError:
        print('[PASS] anchor_twice_rejected'); ok += 1
    total = len(cases) + 1
    print(f'CHECKS : {total}\nERRORS : {total - ok}\nRESULT : {"PASS" if ok == total else "FAIL"}')
    return 0 if ok == total else 1


def main():
    ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='c', required=True)
    r = sp.add_parser('run'); r.add_argument('--select', required=True)
    sp.add_parser('selftest'); sp.add_parser('list')
    sp.add_parser('trace-golden').add_argument('--check', action='store_true')
    a = ap.parse_args()
    if a.c == 'selftest': sys.exit(cmd_selftest())
    if a.c == 'trace-golden':
        reg = json.load(open(REG))
        jobs = [resolve_job(job, reg) for job in reg['jobs']
                if 'trace_of' in job and not job.get('negative')]
        sys.exit(pvm_trace_jobs.generate(ROOT, jobs, run_job, a.check))
    if a.c == 'list':
        for j in json.load(open(REG))['jobs']:
            print(j['selection'], j['id'], j['checks'], 'NEG' if j.get('negative') else '')
        return
    sys.exit(cmd_run(a.select))


if __name__ == '__main__':
    main()
