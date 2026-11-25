# Add a protocol to PVM

Write one transaction, assemble it and load it over the same SPI host
interface used by the protocol demos. This worked example uses a
five-word pulse sender. It is a starting point for understanding the
toolchain and checking a pin waveform. [ISA card](ISA_CARD.md) · [Toolchain guide](TOOLCHAIN.md)

## Write the contract

From idle low, P5 emits two high pulses. Each high pulse lasts 5 µs
with a 5 µs low gap between them. The engine then reaches DONE and
P5 returns to idle low. At a 50 MHz core clock, each of those
intervals is 250 core clocks. At CLKDIV 25, that is ten engine ticks.

## Assemble and build the image

Use Bash, Python 3.10 or later, and a checkout of the review
candidate. Run from the repository root.

```sh
lesson=$(mktemp -d)
export PVM_LESSON="$lesson"

cat > "$lesson/pulse.pvm" <<'PVM'
    set x, 1
pulse:
    set pins, 1 [9]
    set pins, 0 [8]
    jmp x--, pulse
    evt done
PVM

cat > "$lesson/pulse.config.json" <<'JSON'
{
  "0x0100": 25,
  "0x0104": 5,
  "0x0105": 1,
  "0x0405": "0x09"
}
JSON

python3 -m tools.pvm_asm "$lesson/pulse.pvm" "$lesson/pulse.hex"
python3 -m tools.pvm_image "$lesson/pulse.pvm" "$lesson/pulse.image.json" \
  --config "$lesson/pulse.config.json"
cat "$lesson/pulse.hex"
```

`SET_BASE=5` and `SET_CNT=1` map SET bit 0 to P5. The P5 config
selects engine output, push-pull drive and idle low. `[9]` adds
nine ticks after the high SET completes. The low SET and its
eight extra ticks take nine ticks. The loop branch takes the
tenth, giving the low gap its full 5 µs. The assembler prints
five machine words. The image builder adds the register writes,
CRC and image version used by the SPI loader.
[Register map](../spec/03_BUS_AND_REGMAP.md) · [Pin map](../spec/02_PINS_AND_TOP.md)

## Check it at the RTL pins

This single compound check requires the idle and edge sequence,
all three interval lengths, and a successful terminal state.
Use Icarus Verilog and VVP on PATH. The reference run uses Icarus
12.0 for the RTL. The test uses the production Python loader
and the RTL wrapper's SPI pins.

```sh
python3 -m venv "$lesson/venv"
. "$lesson/venv/bin/activate"
python -m pip install -r test/requirements.txt

cat > "$lesson/test_pulse_lesson.py" <<'PY'
import os
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge

from capture_dmx512 import capture_edges
from test_toolchain import SimTransport
from tools.pvm_host import DONE, PVMHost, read_image


@cocotb.test()
async def two_pulses(dut):
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    transport = SimTransport(dut)
    host = PVMHost(transport)
    await transport.wait_cycles(4)
    dut.rst_n.value = 1
    await transport.wait_cycles(4)
    image = read_image(Path(os.environ["PVM_LESSON"]) / "pulse.image.json")
    ready = await bridge(host.load_image)(image)
    assert ready["status"] == 0x42

    edges = []
    capture = cocotb.start_soon(capture_edges(dut, edges))
    await bridge(host.enable)()
    result = await bridge(host.wait_done)()
    capture.cancel()
    assert result["state"] == DONE and result["fault_code"] == 1
    assert [level for _, level in edges] == [0, 1, 0, 1, 0], "PULSE_EDGES"
    _, (rise_1, _), (fall_1, _), (rise_2, _), (fall_2, _) = edges
    intervals = (fall_1 - rise_1, rise_2 - fall_1, fall_2 - rise_2)
    assert intervals == (250, 250, 250), f"PULSE_INTERVALS {intervals}"
    dut._log.info("P5 intervals in core clocks: %s", intervals)
PY

(cd test && PYTHONPATH="..:$lesson" make COCOTB_TEST_MODULES=test_pulse_lesson &&
  python -m cocotb_tools.check_results results.xml)
```

As a negative check, replace `[9]` with `[8]` in the high SET
in the temporary assembly file. Rebuild the image with the same
command and rerun the check. Both high intervals should become
225 core clocks and fail `PULSE_INTERVALS`.
This rerun uses the temporary files under `PVM_LESSON`.
[Positive and negative replay log](../evidence/v1.0_rc/tutorial/pulse_replay.log)

For your own protocol, define the transaction, pins, timing
tolerances, and end state before writing assembly. Use a separate
target model when the protocol reads a bus or depends on a peer
response. Preserve the source, configuration, exact build command,
capture, and a targeted negative result. [Protocol examples](PROTOCOL_MATRIX.md) · [Verification](VERIFICATION.md)
