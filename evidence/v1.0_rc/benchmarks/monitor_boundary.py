"""Compare frozen monitor verdicts with an independent integer reference."""
import sys
from pathlib import Path
import subprocess
import tempfile

src = Path(sys.argv[1])
bench = (src/"tb_rtl/tb_mon.v").read_text()
body=[]
for kind in ("MINIMUM", "MAXIMUM"):
    for t in (231,232,233,237,238,239):
        if kind=="MINIMUM":
            verdict=1 if t>=238 else 2 if t<232 else 3
        else:
            verdict=1 if t<=232 else 2 if t>238 else 3
        body.append(f'measure({kind}, 235, 3, {t}, {verdict}, good);')
        body.append(f'check("M1_{kind}_{t}_EXPECT_{verdict}",good);')
for t in (231,232,233,237,238,239):
    verdict=1 if t>=238 else 2 if t<232 else 3
    body.append(f'stretch({t}, {verdict}, good);')
    body.append(f'check("M1_STRETCH_{t}_EXPECT_{verdict}",good);')
anchor='        measure(MINIMUM, 235, 3, 238, 1, good);'
assert bench.count(anchor)==1
import re
count=re.search(r'localparam(?: integer)? N_CHECKS\s*=\s*(\d+)',bench)
assert count
N=int(count[1])
bench=bench[:count.start(1)]+str(N+18)+bench[count.end(1):]
bench=bench.replace(anchor,"\n".join("        "+line for line in body)+"\n"+anchor)
with tempfile.TemporaryDirectory() as d:
    path=Path(d)
    (path/"bench.v").write_text(bench)
    subprocess.run(["iverilog","-g2005","-s","tb_mon","-o","sim","bench.v",
                    str((src/"src/pvm_mon.v").resolve()), str((src/"src/pvm_presc.v").resolve())],cwd=path,check=True)
    log=subprocess.check_output(["vvp","sim"],cwd=path,text=True)
    print(log,end="")
    assert "RESULT : PASS" in log and log.count("[PASS] M1_")==18

