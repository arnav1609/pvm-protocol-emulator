"""Matched F2 comparison on the frozen core, sampled on the external pin."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

src=Path(sys.argv[1]).resolve()
sys.path.insert(0,str(src))
from tools.pvm_asm import assemble
from tools.pvm_image import build_image

bits=[0,1,1,0,1,0,0,1]
header=(src/"tb_rtl/tb_protocols.v").read_text().split("    task wait_uo")[0]
body=r"""
integer cycles=0, mode_case=0;
reg capture=0, prior=0;
always @(negedge clk) begin
    cycles=cycles+1;
    if(capture && uo[0]!==prior) begin
        $display("EDGE %0d %0d %b",mode_case,cycles,uo[0]);
        prior=uo[0];
    end
end
initial begin
"""
for fabric in (False,True):
    cfg={0x100:10,0x104:5,0x105:1,0x405:0x09}
    if fabric:
        cfg.update({0x200:0x66,0x201:0x66,0x202:0xe8,0x220:249,0x222:5,0x405:0x0b})
        code="".join(f"set fab, {bit} [24]\nset y, 0 [24]\n" for bit in bits[1:])
        code+="set y, 0 [24]\nset y, 0 [24]\nset y, 0 [24]\nevt done\n"
    else:
        code="set pindirs, 1\n"+"".join(f"set pins, {bit} [24]\nset pins, {1-bit} [24]\n" for bit in bits)+"evt done\n"
    image=build_image(assemble(code),config=cfg)
    body+=f"reset_and_halt;mode_case={int(fabric)};\n"
    body+="\n".join(f"write_config(16'h{a:04x},8'h{v:02x});" for a,v in image["writes"])
    body+="""
validate_image(ready);
if(!ready) $finish_and_return(1);
prior=0;capture=1;
write_register(CTRL,3);
repeat(6000) @(negedge clk);
capture=0;
read_register(16'h0f0b,serial_rx);
read_register(16'h0f01,status);
$display("DONE %0d %h %h",mode_case,status,serial_rx);
"""
body+='$finish; end endmodule\n'
with tempfile.TemporaryDirectory() as d:
    p=Path(d)
    (p/'bench.v').write_text(header+body)
    subprocess.run(['iverilog','-g2005','-s','tb_protocols','-o','sim','bench.v',
                    *map(str,sorted((src/'src').glob('*.v')))],cwd=p,check=True)
    raw=subprocess.check_output(['vvp','sim'],cwd=p,text=True)
    print(raw,end='')
for fabric in (0,1):
    trace=[(int(cycle),int(value)) for cycle,value in re.findall(fr'^EDGE {fabric} (\d+) ([01])$',raw,re.M)]
    anchor=trace[0][0]-250
    halves=[value for bit in bits for value in (bit,1-bit)]
    want=[(i*250,b) for i,b in enumerate(halves) if i and b!=halves[i-1]]
    got=[(t-anchor,b) for t,b in trace if t-anchor<4000]
    assert got==want,(fabric,got,want)
    flags=re.search(fr'^DONE {fabric} 44 ([a-f0-9]+)$',raw,re.M)
    assert flags and bool(int(flags[1],16)&2)==bool(fabric)
    print("PASS",("fabric" if fabric else "engine"),"100000 bit/s",len(want),"matched transitions",
          "waveform service instructions",7 if fabric else 16)
