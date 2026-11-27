"""The planned wrapper mutations run on copies with a causal assertion."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
CASES=(
    ("swap-iobuf", "assign pvm_uio_in[p] = protocol_io[p];",
     "assign pvm_uio_in[p] = protocol_io[p == 0 ? 1 : p == 1 ? 0 : p];", "PAD_INPUT_MAPPING"),
    ("invert-iobuf-t", "assign protocol_io[p] = pad_release ? 1'bz : pad_drive;",
     "assign protocol_io[p] = !pad_release ? 1'bz : pad_drive;", "PAD_INPUT_MAPPING"),
    ("drop-miso", ".spi_miso(pvm_uo[7])", ".spi_miso(1'b0)", "SPI_READBACK transaction 1"),
    ("wrong-clock", "assign clk50 = sim_clk50;", "assign clk50 = clk100;", "MMCM_RATIO"),
    ("sda-pull-low", "assign i2c_pullup = 2'b11;", "assign i2c_pullup = 2'b10;", "BOARD_I2C_PULLUP_IDLE"),
    ("scl-pull-low", "assign i2c_pullup = 2'b11;", "assign i2c_pullup = 2'b01;", "BOARD_I2C_PULLUP_IDLE"),
)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog",default="iverilog")
    parser.add_argument("--vvp",default="vvp")
    args=parser.parse_args()
    wrapper=(ROOT/"rtl/pvm_arty_top.v").read_text()
    order=(ROOT/"freeze/handoff/src-order.txt").read_text().splitlines()
    for name, anchor, mutation, verdict in CASES:
        assert wrapper.count(anchor)==1
        with tempfile.TemporaryDirectory() as work:
            directory=Path(work)
            (directory/"mutant.v").write_text(wrapper.replace(anchor,mutation),encoding="ascii")
            (directory/"frames.txt").write_text("5 9f 00 00 00 00 0 80 86 77 33\n",encoding="ascii")
            subprocess.run([args.iverilog,"-g2012","-DSIM","-s","tb_pvm_arty_top","-o","test.vvp",
                            str(ROOT/"sim/tb_pvm_arty_top.v"),"mutant.v",
                            *[str(ROOT/"freeze"/p) for p in order],
                            str(ROOT/"rtl/uart_spi_bridge.v"),str(ROOT/"rtl/i2c_target_fixture.v")],
                           cwd=directory,check=True,timeout=30)
            argv=[args.vvp,"test.vvp"]
            if name!="drop-miso":
                argv.append("+probe_only=1")
            test=subprocess.run(argv,cwd=directory,capture_output=True,text=True,timeout=30)
            log=test.stdout+test.stderr
            print(log,end="")
            if test.returncode==0 or verdict not in log or "WRAPPER_TIMEOUT" in log:
                raise SystemExit(f"Unexpected result from {name}")
            print(f"NEG_KILLED {name} at {verdict}")


if __name__=="__main__":
    main()
