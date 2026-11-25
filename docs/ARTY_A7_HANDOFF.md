# Arty A7 PVM handoff

The source is the public `rtl-freeze` tag at
`b33a9227ac187f791a3733b94ac4e32879b10414`. The fixture is the
Arty A7-100T, part `xc7a100tcsg324-1`. FPGA implementation and
measurements await Kalash’s go-ahead. Once authorized, use
`fpga/arty_a7/` on an FPGA branch for the wrapper, XDC and single Tcl
script that creates `JaneStreet_ASIC_Artix7_FPGA_Run`. Publish raw
capture conditions alongside any result labelled **FPGA-measured
(Artix-7)**. [Frozen checkout](https://github.com/arnav1609/pvm-protocol-emulator/tree/rtl-freeze)

## FPGA integration

The PVM core top is `tt_um_arnav1609_pvm`. Add the 16 sources in
`info.yaml` order and compile as Verilog. Full variant D uses neither
`PVM_NO_FABRIC` nor `PVM_NO_MON`. It needs no additional defines.
The wrapper owns the MMCM (100 MHz to 50 MHz), IOBUFs and board
constraints. Assert reset while the MMCM is unlocked. The external
`rst_n` is active low. D-017 asynchronously asserts the two reset
release stages and releases internal reset after two 50 MHz rising
edges. Hold reset across core clocks during startup. Tie `ena` high
in the FPGA wrapper. The frozen top ignores it.

Every open-drain `uio` uses `uio_oe=1, uio_out=0` for low and
`uio_oe=0` for release. Use `IOBUF.T = !uio_oe` and return
`IOBUF.O` to `uio_in`. Add external 3.3 V pull-ups for SDA and SCL
with a common ground. The guard releases bidirectional pins outside
RUN and sets dedicated outputs to their configured idle levels after
reset. During reset the dedicated outputs reset low.

The frozen sources use `$clog2` in the parametrized FIFO and ordinary
Verilog generate, memories and indexed slices. The instruction RAM
resets its valid bits. Its word array has no initialization file and
the host supplies the program. The source audit found no RTL
`$display`, `$readmem*` or SystemVerilog files. Vivado synthesis of the
Arty wrapper is an FPGA bring-up step.
[Full ordered source list and pin map](https://github.com/arnav1609/pvm-protocol-emulator/blob/rtl-freeze/info.yaml) · [Reset and pin specification](../spec/02_PINS_AND_TOP.md) · [Pin guard](../src/pvm_pin_guard.v)

## Pin mapping and host SPI

| PVM port | Function |
| --- | --- |
| `ui_in[0]`, `ui_in[1]`, `ui_in[2]` | Host SCK, active-low CS and MOSI |
| `uo_out[7]` | Host MISO |
| `ui_in[3]` through `ui_in[7]` | P0 through P4 in ascending order |
| `uo_out[0]` through `uo_out[6]` | P5 through P11 in ascending order |
| `uio[0]` through `uio[7]` | P12 through P19 in ascending order |

Keep CS low for the entire mode 0, MSB-first frame. WRITE sends
`02 A_H A_L D0 ...`. READ sends `03 A_H A_L 00` and clocks one
extra byte per returned data byte. ID sends `9F 00 00 00 00` and
returns `00 50 56 4D 21`. Max host SCK is 50 MHz/16 = 3.125 MHz.
The current RP2350 DemoBoard bit-bang transport requests up to
250 kHz by default, using a minimum 2 µs per half-cycle at 50 MHz.
Interpreter and GPIO overhead reduce the actual SCK. Measure the
wire rate on the board. This host link is separate from any SCK the
loaded protocol generates. [Byte frames and status registers](../spec/03_BUS_AND_REGMAP.md) · [Current host implementation](../tools/pvm_host.py)

## Images and host loader

The handoff includes assembly, configuration, addressed hex, an
instruction-only little-endian binary and the complete SPI image
JSON for each program. Load the JSON. The bare instruction binary
omits configuration, image version, CRC and TX preload. Build
commands and serialized CRCs are in the handoff manifest. The
tested toolchain checkout is `752ebb97824cfd1161581497c22d3c171c4c6ca9`.
The DMX512 initial load and reload use the exact same accepted image.

| Demo | Words | Image version | Preload | CRC-16 |
| --- | ---: | ---: | --- | --- |
| UART TX | 8 | 1 | 35 | 1AA5 |
| SPI mode 0 | 7 | 2 | A6 C9 | 334C |
| I²C write | 18 | 3 | A0 3C | 5C66 |
| DMX512 TX, load and reload | 29 | 1 | Empty | A7C3 |

`pvm_host.py` and `pvm_wire.py` are MicroPython source. The existing
DemoBoard adapter expects the Tiny Tapeout RP2350 MicroPython SDK.
The repo records no tested board firmware or prebuilt UF2. A plain
RP2040 Pico needs its own MicroPython firmware and a transport that
implements `exchange(bytes) -> bytes`. The handoff includes a
hardware-SPI0 adapter example for GP18 SCK, GP19 MOSI, GP16 MISO and
GP17 CS, configured for 250 kHz, mode 0 and a shared ground. Its
wiring and board execution remain to be tested. A desktop Python
program can also use `PVMHost` with an implementation of the same
transport interface. A USB-serial bridge would need a frame
transport on both ends.
[Host instructions and example loading sequence](TOOLCHAIN.md#load-an-image-over-spi)

The host verifies ID, HALTs, writes the image, checks CRC, VALIDATEs,
checks the committed image ID and preloads TX. `host.enable()`
writes CTRL=0x03 and checks RUN or DONE. `host.wait_done()` reports
DONE or raises on FAULT or poll exhaustion. `host.status()`,
`host.read(0x0F12)`, `host.pop_rx()` and `host.read_monitor()`
provide terminal evidence, FIFO levels/data and log entries. Capture
a long DMX512 transmission with host SPI idle, then read DONE.

## Expected captures and readback

| Demo | Pin oracle | DONE PC | IMAGE_ID bytes |
| --- | --- | ---: | --- |
| UART | P5, idle high, 8N1 LSB-first 0x35, 434 core clocks per bit | 7 | A5 1A 01 |
| SPI | P6 clock, P7 MOSI, idle-low mode 0, A6 C9 MSB first, 16 rising clocks | 6 | 4C 33 02 |
| I²C | P12 SDA and P13 SCL, START, A0, ACK, 3C, ACK, STOP. Regular data periods were 320 core clocks with the ideal target. | 17 | 66 5C 03 |
| DMX512 | P5, two 25-slot packets per run, 128 µs BREAK, 16 µs MAB and 4 µs bits | 21 | C3 A7 01 |

All four observed `STATUS=0x44`, `FAULT_CODE=0x01` (normal DONE),
`FIFO_STAT=0x00`, `FLAGS=0x00` and zero monitor counts and entries
after completion. READY was 0x42 before enable. The done-cycle
`FAULT_TIME` depends on the starting timestamp and the run schedule.
Use the waveform and state verdicts for board comparison. The ZIP
contains per-cycle UART, SPI and I²C RTL pin CSVs, the two archived
DMX512 pin traces, the decoder and the measured readback JSON.
[Pin gate](../reports/S14b_protocols_gate.md) · [DMX512 demo and decoder results](DMX512_TX_DEMO.md)

The I²C test uses an ideal responder at 7-bit address 0x50. It ACKs
the address and the single following byte, then watches STOP. The
model held SCL low for an extra 331 core clocks (6.62 µs) on the
first ACK. A 24LC02/AT24C02 strapped to 0x50 can ACK 0xA0 and take
0x3C as its internal word address. The demonstration sends no
following EEPROM data byte, so it demonstrates an addressed bus
transaction. Check the actual part's address straps, supply and
pull-ups. The program also accepts a target that releases SCL
without stretching. Scope the EEPROM capture accordingly.

Real wires add rise time, thresholds, reset and clock-lock
behavior, synchronization phase and possible signal contention.
Use the analyzer to validate idle levels, bit order, pulse width
and ACK releases. A DMX512 physical bus also needs an appropriate
differential line driver and termination.
