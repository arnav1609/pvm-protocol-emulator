# PVM Protocol Emulator

PVM is a programmable serial protocol emulator for Tiny Tapeout IHP.
A host loads an image over SPI. A 32-word engine then drives or samples
pins, a configurable fabric handles selected logic and timing tasks, and
a passive monitor records rule verdicts and measured intervals.

The same RTL runs UART TX, an SPI mode 0 controller and an I²C write with
ACK and clock stretching. The pin-level tests load all three programs
over the host SPI interface. [Protocol checks](reports/S14b_protocols_gate.md)

## Quick start

Use Python 3.10 or later to build the UART image from the repository root.

```sh
python3 -m tools.pvm_image tools/examples/uart_tx.pvm /tmp/pvm-uart.json \
  --config tools/examples/uart_tx.json --tx 0x35
```

Run the RTL regression with Icarus Verilog (`iverilog` and `vvp` on `PATH`).

```sh
python3 tb_rtl/pvm_run.py run --select all
```

The toolchain guide covers all example images, the SPI loader and how to
replay generated images through the RTL wrapper. [Toolchain](docs/TOOLCHAIN.md)

## Design and evidence

| Document | Contents |
| --- | --- |
| [Architecture](docs/ARCHITECTURE.md) | Host interface, engine, fabric, monitor, pins and variants |
| [ISA](docs/ISA.md) | Assembly syntax, encoding and timing |
| [Verification](docs/VERIFICATION.md) | Stage checks, mutation results, trace replay and physical evidence |
| [Datasheet](docs/info.md) | Pinout and getting started |
| [Tools and AI use](docs/AI_USE.md) | Design, verification and evidence tooling |
| [Submission outline](docs/SUBMISSION_WRITEUP.md) | Experiments, demo evidence and remaining deliverables |

The full 8×4 candidate routed at 50 MHz with 33.7187% standard-cell
utilization and +2.461 ns slow-corner setup slack. The acceptance
status and links to physical artifacts are in the CI report.
[Variant D CI](results/ci_S14.md) · [Layout preview](https://arnav1609.github.io/pvm-protocol-emulator/gds_render.png)
