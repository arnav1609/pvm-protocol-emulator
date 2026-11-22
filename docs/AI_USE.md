# Tool and AI use disclosure

## AI assistance

Codex helped translate the project specifications into RTL, construct
the stage and mutation tests, develop the D-016 timing repair, collect
CI evidence, and build the first assembler, image builder and SPI
host loader. A second Codex session developed the assembler and image
builder in parallel. The decision log records project approvals for
interface and timing decisions. Codex also wrote the first spec-derived
ISS and directed lockstep tests, ran the recorded post-freeze protocol
draw, assembled the DMX512 TX demo and assembled the release evidence.
Kalash approved the frozen RTL and supplied the independent owner
verification package.
[Decision log](../spec/DECISIONS.md) · [Freeze review](../reports/weekly_freeze_review.md)

The team still needs to confirm Claude’s role and the artifacts it
assisted before the submission disclosure is finalized.

## Engineering tools

| Tool | Use |
| --- | --- |
| Python | Regression orchestration, trace comparison, assembly, image generation and transport tests |
| Icarus Verilog 12.0 and cocotb | Local RTL simulation and SPI tests |
| Tiny Tapeout Icarus Verilog 13.0 | Functional replay of the three protocol demos using the routed netlist and pinned IHP cell models |
| Verilator 5.032 | Lint for the four build variants and timing-enabled replay of 26 distinct positive RTL bench configurations at two seeds each |
| Yosys 0.52 and ABC | Structural checks and comparative synthesis estimates |
| LibreLane, Tiny Tapeout Actions and the IHP open PDK | Routed GDS/OASIS, physical reports, precheck and design viewer deployment |
| Tiny Tapeout RP2350 MicroPython SDK | Target environment for the DemoBoard SPI adapter. Board test pending. |

[Verification evidence](VERIFICATION.md) · [Physical CI](../results/ci_S14.md)
