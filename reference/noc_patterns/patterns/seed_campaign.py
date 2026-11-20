"""Compile once; run 1,000 independent XSim seed processes with exact ledger validation."""
import argparse
import csv
import ctypes
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
BIN=Path('C:/xilinx_vivado/Vivado/2024.1/bin')

@contextmanager
def system_awake(set_state=None):
    if set_state is None and os.name=='nt':set_state=ctypes.windll.kernel32.SetThreadExecutionState
    if set_state is not None and not set_state(0x80000001):
        raise RuntimeError('could not prevent automatic sleep during campaign')
    try:yield
    finally:
        if set_state is not None:set_state(0x80000000)

def judge_version(text):
    if re.findall(r'^Vivado Simulator v([^\s]+)\s*$',text,re.M)!=['2024.1']:
        raise ValueError('wrong or unproven simulator version')

def judge_seed(text,seed):
    if re.search(r'ERROR:|\[FAIL\]|TB_TIMEOUT|Fatal:',text,re.I):raise ValueError('diagnostic failure')
    for pat,want in [(r'^RESULT\s*:\s*(\w+)\s*$', ['PASS']),
                     (r'^CHECKS\s*:\s*(\d+)\s*$', ['2']),
                     (r'^Errors\s*[:=]\s*(\d+)\s*$', ['0'])]:
        if re.findall(pat,text,re.M|re.I)!=want:raise ValueError('missing/duplicate/failed acceptance line')
    if re.findall(r'^SEED_RESULT seed=(\d+) completed=1 errors=(\d+)\s*$',text,re.M)!=[(str(seed),'0')]:
        raise ValueError('wrong or incomplete seed')
    if '$finish called' not in text:raise ValueError('no bounded bench completion')
    seed_delays(text,seed)

def seed_delays(text,seed):
    rows=re.findall(r'^SEED_LATENCY seed=(\d+) grant=(\d+) response=(\d+)\s*$',text,re.M)
    if len(rows)!=1 or int(rows[0][0])!=seed or any(not 1<=int(v)<=100 for v in rows[0][1:]):
        raise ValueError('missing, duplicate or invalid latency observation')
    return tuple(map(int,rows[0][1:]))

def judge_range_ledger(rows,first,count):
    if len(rows)!=count or [r['seed'] for r in rows]!=list(range(first,first+count)) or any(r['result']!='PASS' for r in rows):
        raise ValueError('incomplete, duplicate, unordered or failed campaign')

def judge_ledger(rows):judge_range_ledger(rows,0,1000)

class ToolFailure(RuntimeError):
    def __init__(self,code,log):
        self.code=code
        super().__init__('tool exited '+str(code)+': '+str(log))

def windows_command(cmd):
    args=[str(v).replace('\\','/') for v in cmd]
    if any(any(c in v for c in ('"','%','\r','\n')) for v in args):
        raise ValueError('unsupported command argument')
    # CMD batch forwarding splits unquoted key=value arguments. Pass an exact
    # command line: CRT list quoting would backslash-escape CMD's inner quotes.
    return 'cmd.exe /d /s /c "'+' '.join('"'+v+'"' for v in args)+'"'

def run(cmd,cwd,log,timeout):
    env=os.environ.copy();env['XILINX_VIVADO']=str(BIN.parent);env['PATH']=str(BIN)+os.pathsep+env.get('PATH','')
    with log.open('wb') as f:
        p=subprocess.Popen(windows_command(cmd),cwd=cwd,env=env,
                           stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,creationflags=0x08000000)
        try:code=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            # This exact PID is the command process created above; never enumerate or kill user jobs.
            subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],capture_output=True)
            raise RuntimeError('owned seed tool timed out; never a pass')
    if code:raise ToolFailure(code,log)

def execute_campaign(out,first=0,count=1000):
    if count not in (100,1000) or first<0 or first+count>1000 or first%100:raise ValueError('unsupported seed range')
    out=out.resolve();work=out/'seed_work';work.mkdir(parents=True,exist_ok=False)
    rtl_files=[ROOT/'rtl/riscv/picorv32_adapter.sv',ROOT/'sim_riscv/tb_random_latency.sv']
    files=rtl_files+[ROOT/'scripts/seed_campaign.py',ROOT/'scripts/run_seed_shard.py']
    manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (out/'compile_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (work/'compile.prj').write_text(''.join('sv xil_defaultlib "'+p.as_posix()+'"\n' for p in rtl_files))
    run([str(BIN/'xvlog.bat'),'-version'],work,work/'version.txt',30)
    judge_version((work/'version.txt').read_text(errors='replace'))
    run([str(BIN/'xvlog.bat'),'--relax','-prj',str(work/'compile.prj')],work,work/'compile.txt',180)
    run([str(BIN/'xelab.bat'),'--relax','--debug','typical','xil_defaultlib.tb_random_latency','-s','seed_snapshot'],work,work/'elaborate.txt',180)
    (work/'run.tcl').write_text('run all\nquit\n')
    rows=[];failed_attempts=[];campaign_start=time.monotonic()
    for seed in range(first,first+count):
        if time.monotonic()-campaign_start>6900:raise RuntimeError('campaign budget exhausted; incomplete seeds never pass')
        start=time.monotonic()
        for attempt in (1,2):
            log=work/f'seed_{seed:04d}_attempt{attempt}.log'
            try:
                run([str(BIN/'xsim.bat'),'seed_snapshot','-sv_seed',str(seed+1),'-tclbatch',str(work/'run.tcl'),'-testplusarg',f'seed={seed}','-log',str(log)],
                    work,work/f'process_{seed:04d}_attempt{attempt}.txt',120)
            except ToolFailure as e:
                failed_attempts.append(dict(seed=seed,attempt=attempt,exit_code=e.code,log=log.relative_to(out).as_posix()))
                (out/'failed_attempts.json').write_text(json.dumps(failed_attempts,indent=2)+'\n')
                # Retry once only when the bench fully passed and the tool failed at shutdown.
                # A timeout or failed/unfinished bench is never accepted and never retried here.
                judge_seed(log.read_text(errors='replace'),seed)
                if attempt==2:raise
                continue
            judge_seed(log.read_text(errors='replace'),seed)
            break
        grant_delay,response_delay=seed_delays(log.read_text(errors='replace'),seed)
        rows.append(dict(seed=seed,sv_seed=seed+1,result='PASS',exit_code=0,attempt=attempt,grant_delay=grant_delay,response_delay=response_delay,
                         seconds=round(time.monotonic()-start,3),log=log.relative_to(out).as_posix(),
                         sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
        (out/'seed_progress.json').write_text(json.dumps(dict(completed=len(rows),last_seed=seed)))
        if (seed+1)%50==0:print(f'SEED_PROGRESS {seed+1}/1000',flush=True)
    judge_range_ledger(rows,first,count)
    with (out/'seed_results.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    if any(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h for p,h in manifest.items()):raise ValueError('source drift')
    (out/'seed_results.json').write_text(json.dumps(dict(tool='Vivado/XSim 2024.1',sources=manifest,first_seed=first,seed_count=count,
                                                       seeds=rows,failed_attempts=failed_attempts),indent=2))
    if count==1000:print('SEED_CAMPAIGN: PASS seeds=1000 independent_processes=1000 checks_per_seed=2')
    else:print(f'SEED_SHARD: PASS first={first} seeds=100 independent_processes=100 checks_per_seed=2')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    with system_awake():execute_campaign(a.out)

if __name__=='__main__':main()
