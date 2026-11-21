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
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=test,test_toolchain)
```

The RTL replay assembles each demo, loads it through the production
host API over simulated SPI, and reads back status, image ID, FIFO
level, instruction memory and configuration. Run the S14b registry
jobs to check the pin waveforms. The independent instruction-set
simulator is still pending. [Verification](VERIFICATION.md)
