## How it works

PVM is a reprogrammable protocol emulator for Tiny Tapeout IHP. The host
loads an instruction image and pin configuration over SPI. The on-chip
state machine checks the image CRC and pin configuration before it enables
the program. The pin guard selects the configured owners and returns
pins to their idle or high-impedance states outside RUN.

The current integration covers host SPI, configuration and validation,
instruction storage, the instruction engine, both FIFOs, and pin safety.
The programmable pin fabric and passive monitor are planned for later RTL stages.

## How to test

Run `make` in `test/` with Icarus Verilog and the Python dependencies in
`test/requirements.txt`. The smoke test reads the SPI ID, loads and
validates a small image, reads back its committed ID, and checks that
HALT restores the configured idle output and releases the bidirectional
pins. The SPI interface uses mode 0, MSB first, at up to one sixteenth of
the core clock.
