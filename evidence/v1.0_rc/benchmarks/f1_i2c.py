"""Directed matched F1 transmit-one workload on PVM, using real SPI and pins."""
from pathlib import Path
import sys
import subprocess
import tempfile

src=Path(sys.argv[1]).resolve()
sys.path.insert(0,str(src))
from tools.pvm_asm import assemble
from tools.pvm_image import build_image

template=(src/"tb_rtl/tb_protocols.v").read_text().split("    task wait_uo")[0]
program="""set pins, 3 side 1
set pindirs, 3 side 1
set pins, 2 side 1
set x, 7 side 0
loop:
set pins, 1 side 0
wait 1 pin 13 side 1
{probe}
jmp x--, loop side 1
evt done side 1
"""
body=r"""
integer cycle=0, arm=0, hit=0, rises=0, last_rise=0, min_period;
integer mode_case, divisor, first_rise, span_total, until_collision;
reg prior=1, bad_after_loss=0;
always @(posedge clk) begin
    cycle=cycle+1;
    if(arm!=0 && scl===1'b1 && prior===1'b0) begin
        rises=rises+1;
        if(last_rise!=0 && cycle-last_rise<min_period) min_period=cycle-last_rise;
        if(rises==1) first_rise=cycle;
        if(rises==8) span_total=cycle-first_rise;
        last_rise=cycle;
    end
    if(hit!=0 && cycle>=hit+4 && uio_oe[1:0]!==0) bad_after_loss=1;
    prior=scl;
end
task run_case(input integer collide);
begin
    rises=0; last_rise=0; min_period=100000; hit=0; bad_after_loss=0; span_total=0;
    validate_image(ready);
    if(!ready) $finish_and_return(1);
    // Arm when ENABLE is accepted, independently of the long SPI frame.
    arm=1;
    fork
        write_register(CTRL,3);
        begin
            if(collide!=0) begin
                for(until_collision=0;until_collision<4000 && rises<2;until_collision=until_collision+1) @(negedge clk);
                if(rises==2) begin target_sda_low=1; hit=cycle; end
            end
        end
    join
    repeat(2000) @(negedge clk);
    arm=0;
    read_register(16'h0f01,status);
    read_register(16'h0f0b,serial_rx);
    $display("OBS variant=%0d div=%0d collision=%0d rises=%0d min_cycles=%0d span7=%0d flags=%h status=%h drive_after_4=%0d",
             mode_case,divisor,collide,rises,min_period,span_total,serial_rx,status,bad_after_loss);
    target_sda_low=0; hit=0;
end
endtask
initial begin
"""
for sem in ('fabric','software'):
    software=sem=='software'
    probe='jmp pin, good side 1\nevt done side 1\ngood:' if software else ('')
    asm=program.format(probe=probe)
    words=assemble(asm,side_count=1)
    for d in (1,2,4,8,16,32):
        config={0x100:d,0x102:12,0x104:12,0x105:2,0x107:13,0x108:1,
                0x109:12,0x40c:0x11,0x40d:0x12}
        if not software: config|={0x224:0x11,0x225:12,0x226:13}
        image=build_image(words,config=config)
        for collide in (0,1):
            body+=f"reset_and_halt; mode_case={int(software)}; divisor={d};\n"
            body+="\n".join(f"write_config(16'h{a:04x},8'h{v:02x});" for a,v in image["writes"])
            body+=f"\nrun_case({collide});\n"
body+='$finish; end\ninitial begin #200000000; $finish_and_return(2); end\nendmodule\n'
with tempfile.TemporaryDirectory() as w:
    p=Path(w)
    (p/'bench.v').write_text(template+body)
    subprocess.run(['iverilog','-g2005','-s','tb_protocols','-o','sim','bench.v',
                    *map(str,sorted((src/'src').glob('*.v')))],cwd=p,check=True)
    run=subprocess.run(['vvp','sim'],cwd=p,text=True,capture_output=True,timeout=180)
    result=run.stdout
    if run.returncode: print(result,end=''); run.check_returncode()
    print(result,end='')
    rows={}
    for line in result.splitlines():
        if line.startswith("OBS "):
            row=dict(field.split("=") for field in line.split()[1:])
            rows[tuple(int(row[key]) for key in ("variant","div","collision"))]=row
    assert len(rows)==24
    for variant in (0,1):
        for divisor in (4,8,16,32):
            good=rows[variant,divisor,0]
            hit=rows[variant,divisor,1]
            assert good["rises"]=="8" and good["flags"]=="00" and good["status"]=="44"
            assert int(good["span7"])==7*(4+variant)*divisor
            assert hit["rises"]=="2" and hit["drive_after_4"]=="0"
            assert hit["flags"]==("00" if variant else "01")
    assert rows[1,2,1]["drive_after_4"]=="1"


