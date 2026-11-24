# Tool and AI use disclosure

## AI assistance

Codex helped translate the project specifications into RTL, construct
the stage and mutation tests, develop the D-016 timing repair, collect
CI evidence, and build the first assembler, image builder and SPI
host loader. A second Codex session developed the assembler and image
builder in parallel. The decision log records project approvals for
interface and timing decisions. Codex also wrote the first spec-derived
ISS and directed lockstep tests, ran the recorded post-freeze protocol
draw, assembled the DMX512 TX demo and organized the release evidence.
Codex helped draft and check the Stage 8 manuscript and reproduction
instructions against the archived measurements. Kalash approved the
frozen RTL and supplied the independent owner verification package. Heet independently reviewed
the digital 1-Wire and SWD fit-study models.
[Decision log](../spec/DECISIONS.md) · [Freeze review](../reports/weekly_freeze_review.md)

Claude helped draft the RTL milestone plan and the pre-freeze handoff
for Kalash. The source handoff credits Claude with the D-008 schedule
proposal, the CODEX_CONTINUE work order and the pre-freeze notes that
proposed clarifying monitor timestamp behavior, removing the reset
synchronizer attribute and preserving golden trace bytes. The work
order also proposed the Verilator replay criteria and the experiment
and gate-replay plan. The project decision log records the approved
scope.
[Approved decisions](../spec/DECISIONS.md)

## Engineering tools

| Tool | Use |
| --- | --- |
| Python | Regression orchestration, trace comparison, assembly, image generation and transport tests |
| Icarus Verilog 12.0 and cocotb | Local RTL simulation and SPI tests |
| Tiny Tapeout Icarus Verilog 13.0 | Zero-delay functional replay of UART, SPI, I²C and DMX512 using the routed netlist and pinned IHP cell models |
| Verilator 5.032 | Lint for the four build variants and timing-enabled replay of 26 distinct positive RTL bench configurations at two seeds each |
| Yosys 0.52 and ABC | Structural checks and comparative synthesis estimates |
| LibreLane, Tiny Tapeout Actions and the IHP open PDK | Routed GDS/OASIS, physical reports, precheck and design viewer deployment |
| Tiny Tapeout RP2350 MicroPython SDK | Target environment for the DemoBoard SPI adapter. Board test pending. |

[Verification evidence](VERIFICATION.md) · [Physical CI](../results/v1.0_routed.md)
