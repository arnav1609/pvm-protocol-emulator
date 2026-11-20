## How it works

PVM is a reprogrammable protocol emulator planned for Tiny Tapeout IHP. The
design will load a program and pin configuration over SPI, drive protocol
signals with a small instruction engine and programmable pin logic, and
observe timing with a passive monitor.

The setup baseline uses the Tiny Tapeout template adder. It adds two
unsigned 8-bit inputs, A on the dedicated input pins and B on the
bidirectional pins, and exposes the low eight bits on the dedicated
outputs. The baseline adder is combinational.

## How to test

The template test drives 20 on the dedicated inputs and 30 on the
bidirectional inputs, then checks for 50 on the dedicated outputs. Run
`make` in `test/` with Icarus Verilog and the Python dependencies in
`test/requirements.txt`, or check the repository's test workflow.
