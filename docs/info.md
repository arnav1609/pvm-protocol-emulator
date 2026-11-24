## How it works

PVM is a reprogrammable protocol emulator for Tiny Tapeout IHP. The host
loads an instruction image and pin configuration over SPI. The on-chip
state machine checks the image CRC and pin configuration before it enables
the program. The pin guard selects the configured owners and returns
pins to their idle or high-impedance states outside RUN.

The instruction engine sequences pin operations, waits, and transfers
through two FIFOs. The pin fabric provides four programmable LUTs,
counter-driven phase and Manchester encoding, and an open-drain
arbitration guard. The passive monitor evaluates programmable timing
rules and exposes verdict counters and a four-entry log over host SPI.

## How to test

In `test/`, run `make COCOTB_TEST_MODULES=test` with Icarus Verilog and
the Python dependencies in `test/requirements.txt`. Check the verdict
with `python -m cocotb_tools.check_results results.xml`. The smoke test reads the SPI ID, loads and
validates a small image, reads back its committed ID, and checks that
HALT restores the configured idle output and releases the bidirectional
pins. The SPI interface uses mode 0, MSB first, at up to one sixteenth of
the core clock.

The full RTL regression runs with
`python3 tb_rtl/pvm_run.py run --select all` from the repository root.
The S14b tests check UART TX 0x35 on P5, SPI mode 0 clock and data on
P6 and P7, and an open-drain I²C write to address 0x50 on P12 and P13.
The I²C target model acknowledges both bytes and exercises clock
stretching. The toolchain guide shows how to generate and load each
image. [Toolchain guide](TOOLCHAIN.md)

The default build includes the engine, fabric, and monitor.
`PVM_NO_FABRIC` and `PVM_NO_MON` select the experiment variants
while keeping the same top-level ports.
