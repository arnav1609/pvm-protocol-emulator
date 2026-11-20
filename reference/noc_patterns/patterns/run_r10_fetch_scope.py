"""Diagnostic: real-CPU execution of MMIO data, before/after the planned DMEM-only guard.

Runs only copied sources. GAP_CONFIRMED is a finding, not design acceptance.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from seed_campaign import BIN,run,system_awake
from dual_lane_verify import judge
from make_merged_sources import RISCV_SOURCES
from run_r10_coverage import checked_log

ROOT=Path(__file__).resolve().parents[1]
SOURCES=['rtl/dual_lane/NOC_PKG.sv']+RISCV_SOURCES+['sim_riscv/tb_r10_mmio_fetch.sv']

def execute(out,guard):
    out.mkdir(parents=True,exist_ok=False)
    sources=[]
    for rel in SOURCES:
        src=ROOT/rel;dst=out/'sources'/rel;dst.parent.mkdir(parents=True,exist_ok=True)
        data=src.read_text(encoding='utf-8-sig')
        if guard and rel=='rtl/riscv/addr_decode.sv':
            anchor='                else if (is_dmem) begin'
            if data.count(anchor)!=1:raise ValueError('decoder guard anchor drift')
            data=data.replace(anchor,
                "                else if (is_dmem && local_is_fetch_i) begin\n"
                "                    local_gnt_o = 1'b1; state_d = ERR_RESP;\n"
                "                end\n\n"+anchor)
        dst.write_text(data,encoding='utf-8',newline='\n');sources.append(dst)
    manifest={r:hashlib.sha256((ROOT/r).read_bytes()).hexdigest() for r in SOURCES}
    (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (out/'compile.prj').write_text(''.join(('verilog' if p.suffix=='.v' else 'sv')+
        ' xil_defaultlib "'+p.as_posix()+'"\n' for p in sources))
    run([BIN/'xvlog.bat','--relax','-prj',out/'compile.prj'],out,out/'compile.log',180)
    checked_log(out/'compile.log')
    run([BIN/'xelab.bat','xil_defaultlib.tb_r10_mmio_fetch','--relax','--mt','2','--standalone',
        '--debug','typical','-s','scope'],out,out/'elaborate.log',300)
    checked_log(out/'elaborate.log')
    env=os.environ.copy();v=BIN.parent
    env['PATH']=os.pathsep.join([str(v/'lib/win64.o'),str(v/'lib/win64.o/Default'),
        str(v/'tps/mingw/6.2.0/win64.o/nt/x86_64-w64-mingw32/lib'),env.get('PATH','')])
    with (out/'simulate.log').open('wb') as f:
        p=subprocess.Popen([str(out/'xsim.dir/scope/axsim.exe')],cwd=out,env=env,
            stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,creationflags=0x08000000)
        try:code=p.wait(timeout=60)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill.exe','/PID',str(p.pid),'/T','/F'],capture_output=True)
            raise RuntimeError('diagnostic timeout; not a result')
    if code:raise RuntimeError('diagnostic simulator exit '+str(code))
    result=judge((out/'simulate.log').read_text(errors='replace'),
        dict(checks=3,config=dict(TOP='tb_r10_mmio_fetch',CHECKS=3)),
        {s:dict(exitCode=0,timedOut=False,interrupted=False) for s in ['compile','elaborate','simulate']},
        manifest,{r:hashlib.sha256((ROOT/r).read_bytes()).hexdigest() for r in SOURCES})
    return dict(dmem_only_guard=guard,observed=result)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
    with system_awake():
        result=[execute(a.out.resolve()/name,g) for name,g in [('baseline',False),('dmem_guard_only',True)]]
    (a.out/'finding.json').write_text(json.dumps(result,indent=2)+'\n')
    print('R10_FETCH_SCOPE: GAP_CONFIRMED cases=2 checks_per_case=3')

if __name__=='__main__':main()
