# PVM toolchain

Use Python 3.10 or later for the desktop tools. The assembler and image
builder use the Python standard library. Run the commands below from
the repository root.

## Build the demo images

```sh
python3 -m tools.pvm_image tools/examples/uart_tx.pvm /tmp/pvm-uart.json \
  --config tools/examples/uart_tx.json --tx 0x35
python3 -m tools.pvm_image tools/examples/spi_mode0.pvm /tmp/pvm-spi.json \
  --config tools/examples/spi_mode0.json --tx 0xA6 --tx 0xC9
python3 -m tools.pvm_image tools/examples/i2c_write.pvm /tmp/pvm-i2c.json \
  --config tools/examples/i2c_write.json --tx 0xA0 --tx 0x3C
```

| Demo | Expected pins and data |
| --- | --- |
| UART | P5 (`uo_out[0]`) sends 0x35 as 8N1. At a 50 MHz core clock, each bit spans 434 core cycles, about 115,207 baud. |
| SPI mode 0 | P6 (`uo_out[1]`) is SCK and P7 (`uo_out[2]`) is MOSI. The controller sends 0xA6 then 0xC9, MSB first. |
| I²C write | P12 (`uio[0]`) is SDA and P13 (`uio[1]`) is SCL. Both are open drain and require pull-ups. The target at 7-bit address 0x50 acknowledges the write address and data byte 0x3C, and may stretch SCL. |

The I²C example uses 0xA0 as the address byte on the bus. The checked
target model supplies both ACKs and stretches the first ACK clock.
[S14b bit-level checks](../reports/S14b_protocols_gate.md)

For a separate machine-word listing, specify the same side-set
width as in the image configuration.

```sh
python3 -m tools.pvm_asm tools/examples/uart_tx.pvm /tmp/pvm-uart.hex --side-count 0
```

Configuration JSON maps register addresses to byte values. Addresses
and values may use strings such as `"0x0405"` and `"0x29"`. The builder
fills unspecified writable configuration bytes with zero and derives
default ENTRY_PC and wrap bounds from the assembled words. It emits a
`pvm-image-v1` JSON object with an image version, CRC-16/CCITT-FALSE,
ordered address-byte writes and up to four TX preload bytes. Writing
all configurable bytes lets an image replace the prior configuration
deterministically. The CRC covers IMEM, configuration and IMAGE_VER
writes in their serialized order. [ISA](ISA.md) · [Register map](../spec/03_BUS_AND_REGMAP.md)

## Load an image over SPI

On a Tiny Tapeout DemoBoard with the RP2350 MicroPython SDK, copy
`tools/pvm_host.py`, `tools/pvm_wire.py` and the generated JSON to the
board. Select the PVM project on a shuttle that includes it. The
adapter assumes RP control of the dedicated inputs, with SCK, CS_n
and MOSI on `ui_in[2:0]` and MISO on `uo_out[7]`. Start the project
clock and use its actual frequency for `core_clk_hz`. The example
assumes an already-running 50 MHz project clock.

```python
from ttboard.demoboard import DemoBoard
from pvm_host import DemoBoardSPI, PVMHost, read_image

board = DemoBoard.get()
board.shuttle.tt_um_arnav1609_pvm.enable()
host = PVMHost(DemoBoardSPI(board, core_clk_hz=50_000_000))
host.load_image(read_image("pvm-uart.json"), enable=True)
print(host.wait_done())
```

Use `enable=False` to leave the image committed in READY, then call
`host.enable()` to start it when the receiver or analyzer is ready.
The loader checks the PVM ID, clears the previous program, verifies
the device CRC, checks the committed image ID and preloads TX before
ENABLE. A different transport can provide `exchange(frame) -> bytes`,
which transfers one complete SPI frame with a single CS assertion.
The adapter bounds SCK to one sixteenth of the project clock. Physical
DemoBoard validation is pending.
[Pin specification](../spec/02_PINS_AND_TOP.md) · [Tiny Tapeout DemoBoard guide](https://tinytapeout.com/guides/get-started-demoboard-etr/)

## Reproduce the checks

```sh
python3 -m unittest discover -s tools/tests -v
python3 -m pip install -r test/requirements.txt
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=test,test_toolchain &&
  python -m cocotb_tools.check_results results.xml)
```

The RTL replay uses the public assembler, image builder and host loader
to assemble, load, commit and enable all three images in one simulation.
It reads back the programmed image and checks the actual demo pins at
50 MHz. The I²C replay uses the existing S14b ideal pull-up, two-ACK and
first-ACK stretch scenario. It exercises reload between images and
checks that HALT preserves the prior DONE diagnostics. S14b's original
pin-waveform and mutant jobs remain available through the RTL runner.
[Pin-level check specification](../reports/S14b_protocols_gate.md)

## Initial instruction-set simulator

`tools/pvm_iss.py` interprets the 32-word ISA from spec 03 §3.2,
spec 04, and D-013 through D-015. Use it with a validated
`pvm-image-v1` image. Each `step` advances one core cycle after
ENABLE and takes the synchronized engine inputs for that edge.

```python
from tools.pvm_host import read_image
from tools.pvm_iss import Engine, State

model = Engine.from_image(read_image("/tmp/pvm-uart.json"))
while model.state == State.RUN:
    model.step()
print(model.state.name, model.fault_pc)
```

Use a cycle budget for programs that wait for external inputs or loop.
The model decodes the eight instruction classes and includes delay,
side-set, scratch and shift registers, WAIT, FIFO transfers, EXEC and
instruction faults. Model unit tests cover WIDE transfers, EXEC, timeout and fault cases.
RTL lockstep matched 13,848 cycles across UART, SPI and I²C and 7,680
cycles across five directed stall, branch, FIFO and shift scenarios.
EXEC, automatic FIFO transfers and prescaled timeout and fault behavior
remain open in the RTL lockstep campaign.
SPI framing and image validation, input synchronization, physical pin
drive, PINFABRIC and SPECMON belong to the surrounding system. The RTL
replay supplies synchronized pin values at the engine boundary and
checks the raw protocol waveforms in a separate observer.
[ISA spec](../spec/04_ISA.md) · [Model](../tools/pvm_iss.py) · [Replay evidence](VERIFICATION.md#demo-lockstep)

[ISS authorship and independent spot-check list](ISS_PROVENANCE.md)

### Windows trace regeneration follow-up

The standalone `python tb_rtl/pvm_run.py trace-golden --check` command
reported different bytes in the owner's Windows checkout. All four
regenerated traces matched after line-ending normalization. The
committed golden CSV hashes and registered D-016 comparisons passed
on Windows. Track making regeneration byte-stable on Windows and Linux
as a tooling-only fix, with the existing golden vectors and provenance
as the acceptance reference. The owner verified a trial separately.
[Windows regression](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44922358383)
