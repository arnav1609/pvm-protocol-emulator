# PVM on the Digilent Arty A7-100T

The FPGA implementation runs the 16 frozen PVM RTL files at 50 MHz. The
wrapper adds clock and reset, a USB UART-to-SPI bridge, an onboard I²C
target fixture, and a 12-probe Integrated Logic Analyzer (ILA). Four
protocol demos run through one J10 USB data cable. DMX512 is loaded and
captured twice. [Implementation and FPGA-measured results](results/README.md)

## Prepare the inputs

Copy these two archived inputs into `fpga/arty_a7/inputs/`. Both are in
`PVM_FPGA_A1_Arnav_Handoff.zip` under
`04_FPGA_ARTY_A7/pvm_fpga_arty_a7/inputs/`. Use the pinned archives supplied
with the handoff so the demo programs and their reference traces stay in sync.

| Input | SHA-256 |
| --- | --- |
| `PVM_rtl-freeze_b33a922.zip` | `f937ee045fd5d2ea2af42326fe25d2fd9ed810470ba12ea9c44adfc3ae978774` |
| `PVM_Arty_A7_Handoff_b33a922.zip` | `9ced043a0db5fc476f68192e477d4d93dea0aed906a6de56e70c6cbe15d2b92d` |

From the repository root, extract and check the ordered RTL. The Tcl
launchers perform the same preflight.

```powershell
python -B fpga/arty_a7/scripts/extract_freeze.py
python -B fpga/arty_a7/scripts/verify_sources.py
```

## Build in Vivado 2024.1

Use Git, Python 3.12 or later and Vivado with support for
`xc7a100tcsg324-1`. From the repository root, choose a new, short build
directory. This example runs implementation through bitstream generation,
checks both setup and hold slack, and writes design reports beside the
project. The programming files are in `JaneStreet_Vivado_Run.runs/impl_1/`.

```powershell
vivado -mode batch -source fpga/arty_a7/scripts/create_project.tcl -tclargs build C:/pvm_arty
```

To install the same sources into an existing `JANE_STREET.xpr`, use its
full path in the Tcl Console and then generate the bitstream as usual.
The updater checks the project name, part, constraints and analyzer
configuration before making changes to the open project.

```tcl
source {C:/checkout/fpga/arty_a7/scripts/update_jane_street.tcl}
pvm_board_update::apply {C:/project/JANE_STREET.xpr}
```

## Program and capture

1. Identify the Arty A7-100T board revision, connect a J10 USB data cable,
   set SW0 high, and leave J3 and the Pmod headers empty. This enables the
   internal target and uses the board's J3 pull-ups.
2. In Vivado Hardware Manager, select the XC7A100T, set JTAG to 10 MHz or
   lower, and program the matching `pvm_arty_top.bit` and `debug_nets.ltx`
   from the same implementation. LD4 and LD5 should stay on, LD6 should
   blink, and one ILA should appear.
3. Install pySerial `3.5` for the Python executable on `PATH`. Find the USB
   UART port with `python -m serial.tools.list_ports -v`. Run the capture in
   the same Hardware Manager Tcl Console. Replace the example path and COM
   number with your own.

```tcl
source {C:/checkout/fpga/arty_a7/scripts/run_pvm_ila.tcl}
pvm_ila_run::all COM3
```

The launcher arms the analyzer before each event. It records five UART
readbacks and six waveforms, then checks the saved captures. Find the run
under `fpga/arty_a7/board_results/auto_*`. The serial port supports one
capture session at a time.

For an operator-armed capture, use the Windows launcher from the
repository root and arm each trigger before pressing Enter.

```powershell
.\fpga\arty_a7\scripts\Run-PvmBoard.ps1 -Port COM3
```

Use one 131,072-sample window and trigger position 1024. Arm the reset
before starting the launcher. Use the analyzer CSV export feature or
`scripts/export_ila.tcl`.

| Event | Trigger | File |
| --- | --- | --- |
| Host reset | Probe 9 falling | `reset.csv` |
| UART TX | Probe 0 falling | `uart.csv` |
| SPI mode 0 | Probe 1 rising | `spi.csv` |
| I²C write | Probe 3 falling and probe 4 high | `i2c.csv` |
| DMX512 initial and reload | Probe 0 falling for each run | `dmx512_run1.csv` and `dmx512_run2.csv` |

Save the six CSVs with `readback.jsonl` from that run. Check the readback
sequence and waveforms with
`.\fpga\arty_a7\scripts\Run-PvmBoard.ps1 -Check C:/path/to/capture`.
[Wiring and probe mapping](docs/WIRING.md) · [PC host](host/README.md)

## Check the host and capture reader

With the pinned archives in place, run the Python suite from the repo
root. For the wrapper simulation, extract the freeze first and use Icarus
Verilog 12 or later.

```bash
python -B -m unittest discover -s fpga/arty_a7/sim -p "test_*.py"
bash fpga/arty_a7/sim/run_icarus.sh --output /tmp/pvm-arty-sim
```
