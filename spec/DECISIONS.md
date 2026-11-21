# PVM DECISIONS

Amends PVM v2.1 Frozen Baseline (19 Nov 2026). Change requires an entry here agreed by Kalash and Arnav.

## D-001 — F1 redefined: arbitration-loss guard, not SDA release
Status: ACCEPTED · Date: 2026-11-19

Why: Review is correct: when the controller intends HIGH, SDA is already released, so forcing OE=0 at that bit is a no-op. The value is what happens AFTER loss.

Decision: Fabric samples synchronised SDA while synchronised SCL is HIGH and stable ≥ N cycles. Mismatch (intended released, observed LOW) sets sticky ARB_LOST. While ARB_LOST=1, pin_guard blocks every subsequent SDA and SCL drive-enable (both forced Z) until the engine clears it; engine sees ARB_LOST via WAIT FLAG/JMP PIN. Measured benefit: engine-only safe multi-controller I²C must test SDA after every transmitted 1 (extra instructions per bit, lower max SCL, unsafe window if omitted); fabric version needs zero per-bit checks. Metrics: instructions/bit, max SCL rate, worst-case cycles from loss to block (bound k). F1b (optional): fabric response to an unrelated pin event while the engine runs an unrelated program.

## D-002 — Counter cell clocking
Status: ACCEPTED · Date: 2026-11-19

Why: “clock = core or engine tick” was ambiguous.

Decision: Single core clock everywhere. Counter advances only on a synchronous enable: en = 1 (every cycle) or en = engine_tick (divider pulse). No generated, gated or muxed clocks anywhere in PVM; lint/STA checks for this.

## D-003 — Pin configuration fields recalculated
Status: ACCEPTED · Date: 2026-11-19

Why: 3 bits/pin cannot encode owner and electrical mode independently.

Decision: Per pin: owner 3 b (none, engine OUT/SET, engine side-set, fabric L0–L3 → 7 codes), mode 2 b (input, push-pull, open-drain, reserved), idle level 1 b, invert 1 b = 7 b × 20 pins = 140 b. Image estimate ≈ 1,140 bits (ESTIMATE until E1). VALIDATE rejects OD on uo and two owners on one pin.

## D-004 — 64×16 IMEM fallback encoding
Status: ACCEPTED (encoding chosen at E1) · Date: 2026-11-19

Why: JMP has addr[4:0]; a 64-word memory needs addr[5].

Decision: Option A (preferred): side-set bits allocated from bit 11 downward in all instructions; bit 12 = delay MSB for non-JMP and addr[5] for JMP (JMP loses 1 delay bit). Option B: JMP cond reduced to 2 bits (drop X≠Y, !OSRE). The fallback is not executable until one option is in isa.yaml with ISS + assembler tests.

## D-005 — Gate semantics split model vs RTL
Status: ACCEPTED · Date: 2026-11-19

Why: A 6 Dec decision cannot prove hardware benefit from models.

Decision: 1 Dec: cycle-model feasibility (F1/F2 functionally sensible). 6 Dec: area/timing feasibility — may cut on cost only. 18 Dec: RTL proof — benefit claimed or feature reduced. 4 Jan: routed, GLS, precheck. Consequence: the fabric’s ports are frozen 11 Dec in a form that still works if F1/F2 fail on 18 Dec (fabric degrades to registered glue behind the same interface; counter tied off).

## D-006 — LUT source mapping per layer
Status: ACCEPTED · Date: 2026-11-19

Why: The 16-source list did not say what layer 1 sees in the last 4 slots.

Decision: Layer 1 (L0, L1): 8 pins of its group + 4 engine bits + {const0, const1, counter_out, ARB_LOST}. Layer 2 (L2, L3): 8 pins + 4 engine bits + {L0, L1, counter_out, const0}. Feed-forward only; no layer-2 → layer-1 path exists in hardware.

## D-007 — FIFO ↔ shift-register width and order
Status: ACCEPTED · Date: 2026-11-19

Why: 8-bit FIFOs vs 16-bit ISR/OSR was unspecified.

Decision: Per-SM config WIDE: 0 → PULL loads one byte into OSR[7:0] (OSR[15:8]=0), PUSH sends ISR[7:0]; 1 → two bytes, little-endian (first byte → [7:0]). Autopull/autopush thresholds 1–8 (WIDE=0) or 1–16 (WIDE=1). Shift direction set per register. Under/overflow with blocking timeout → TIMEOUT fault.

## D-008 — RTL schedule aligned to MicroMinds guide (hard RTL freeze 11 Dec)
Status: APPROVED for this RTL build by the repository owner in chat · Date: 2026-11-20

Why: D-005 put fabric/monitor RTL proof on 18 Dec, but the MicroMinds guide requires all baseline RTL functionally verified by 10 Dec and a hard RTL feature freeze on 11 Dec.

Decision: All 14 RTL stages (including PINFABRIC and SPECMON) are written and stage-verified by 10 Dec. 11-18 Dec: F1/F2/M1 measurements run on the frozen RTL (experiments, not new RTL). If a feature fails its experiment, it is reduced by configuration/tie-off behind the unchanged interface (a documented fix, allowed after freeze), never by new features.

## D-009 — RTL language: Verilog-2005 until G0 proves SystemVerilog
Status: APPROVED for this RTL build by the repository owner in chat · Date: 2026-11-20
Decision: All RTL in Verilog-2005 so it runs unchanged in Vivado XSim, Icarus (CI cocotb) and the TT Yosys flow. Revisit only if the G0 CI test shows SystemVerilog passes the gds flow.

## D-010 — Interface details fixed in the Codex handoff spec
Status: APPROVED for this RTL build by the repository owner in chat · Date: 2026-11-20
Decision: spec/02-07 of the RTL handoff (pin indexing P0-P19, byte bus, SPI frame with f_SCK <= f_clk/16, full register map, ISA semantics, fabric source map, monitor actions, VALIDATE checks, fault codes, 4-entry monitor log) become the interface baseline. Arnav's assembler/ISS/host tool use the same files. Changes only through this log.

## D-011 — House Engineering Method adopted; Codex builds autonomously with weekly human review
Status: APPROVED for this RTL build by the repository owner in chat · Date: 2026-11-20
Why: Kalash asked that the house method (NOC_PQATTEST/docs/methodology/HOUSE_ENGINEERING_METHOD.md v1) govern the PVM handoff and that Codex build while humans review weekly.
Decision: method/HOUSE_ENGINEERING_METHOD.md applies, with the PVM differences in method/PVM_METHOD_ADAPTATION.md (Verilog-2005, active-low rst_n, pvm_run.py instead of dual_lane.py, CI util <= 40 % / WNS >= 0 instead of the 47,550 LUT limit, PVM claim flags). Codex continues to the next stage after a PASS gate; HARD STOP conditions unchanged. Reviews W0 22 Nov, W1 29 Nov, W2 6 Dec, W3 10-11 Dec. The MicroMinds per-stage "other owner reviewed" tick becomes the weekly review tick (recorded in STATUS columns XSim / ISS cross-check).

## D-012 — HALT starts with clear FIFO status and contents
Status: APPROVED by Kalash in chat before S06 · Date: 2026-11-20

Decision: HALT clears WR_REJ, TX_OVF, RX_UNF, and both FIFOs. ENABLE preserves FIFO contents so TX can be preloaded. See [interface revision 1](rev/PVM-IF-rev1-HALT-CLEARS.md).

## D-013 — OSR shift count at reset and ENABLE
Status: APPROVED in chat before S09 · Date: 2026-11-20

Decision: Initialize `osr_cnt` to `5'd16` at reset and ENABLE. This
clarifies [the engine state table](04_ISA.md#2-engine-state). The OSR is empty
at initialization for every supported PULL_THRESH, including 16 in WIDE mode.

## D-014 — WIDE FIFO beats follow engine ticks
Status: APPROVED in chat before S10 · Date: 2026-11-20

Decision: Wait for capacity for both bytes before starting, including on
an instruction with BLOCK clear. Transfer low and
high bytes on consecutive engine ticks, then begin delay and update the PC.
The same timing applies to a WIDE OUT autopull or IN autopush.
[ISA rules](04_ISA.md#wide-fifo-timing-d-014)

## D-015 — EXEC delay, parent PC, and injected faults
Status: APPROVED in chat before S10 · Date: 2026-11-20

Decision: Apply the parent delay before issuing the injected word. The
injected word uses its own timing and the parent's PC, and nested EXEC
faults as ILLEGAL_OP. OUT EXEC consumes a 16-bit shifted word. MOV EXEC
uses the value after the MOV operation. Injected words bypass IMEM
validity, and their faults report the parent's PC.
[ISA rules](04_ISA.md#exec-timing-and-faults-d-015)

## D-016 — S11 G2 timing repair at 50 MHz

Approved by Kalash in chat on 20 November 2026.

1. Give image validation its own `ENTRY_PC` validity lookup and address
   the engine instruction port directly from the engine.
2. If repair 1 leaves slow-corner setup slack below +1.0 ns, register the
   next instruction word at issue, including injected EXEC words, and
   derive the pin mapping once from the static configuration. Preserve
   branch, wrap, EXEC, and all other tick-level behavior.

Acceptance requires the unchanged frozen S09–S11 checks and full
regression to pass. For D-016, Kalash designated the accepted pre-repair
RTL at `4b13f45` as the trace reference. The four `+TRACE` CSV
comparisons must match every core cycle, and the one-cycle `out_val`
delay mutant must fail its trace comparison. The ISS is a separate
toolchain deliverable. The 8×4 design must meet
the area limit and have at least +1.0 ns routed setup slack at
`nom_slow_1p08V_125C` with the existing 20 ns clock, with GDS, Tiny
Tapeout precheck, gate-level simulation, and the Pages viewer green.
S12 remains blocked until G2 passes. Clock and pin-map changes require
a new owner decision. If both repairs miss the timing target, report
the remaining path and stop for that decision.
[Original G2 failure](../results/g2_area_timing.md) · [Trace provenance](../tb_rtl/vectors/golden_provenance.json)

## D-017 — Synchronize reset release

Approved in chat on 21 November 2026 for the optimization candidate.
Assert the core reset asynchronously and release it after two rising
clock edges. Retain the existing synchronous reset consumers.
Keep D-017 in the RTL. It is present in `1a258a1`, which passed the
reset regression and all physical checks in run `44862976826`.
[Reset interface and verification](rev/PVM-IF-D017-RESET-RELEASE.md) · [Physical acceptance](../results/opt_area_timing.md)

## D-018 — Optimize monitor and engine area

Approved in chat on 21 November 2026 for candidate implementation and
physical evaluation. Evaluate O1b/O2/O3/O4 with D-017 at 50 MHz against
the predeclared timing, area, and physical test criteria.
All criteria passed on `1a258a1`. The approved branch integrates all
four optimizations.
[Optimization decision and acceptance](rev/PVM-AREA-D018.md) · [Candidate report](../results/opt_area_timing.md)

## D-019 — Time-box the 32-word fit check before freezing

Approved in chat on 21 November 2026. Require 1-Wire and SWD fit
checks with a target bus model and measured timing. If both fit in
32 words, proceed with the freeze once the simulator and review gate
passes. If either exceeds 32 words after one optimization pass, stop
for the owner's D-004 decision. If the programs are unfinished on
26 November, keep 32 words and record the risk.

The 1-Wire transaction uses 19 words and the SWD read uses 32, with
both pin-model checks and directed mutations accepted. Retain the
32-word memory.

WS2812, PS/2 receive, and DMX512 transmit follow the freeze. The
outsider draws from all five candidates after the tag. If 1-Wire or
SWD is drawn, disclose the pre-freeze study.
[Fit scope and results](../results/fit_study.md)

## D-020 — Use Verilator for the freeze simulator gate

Decision recorded from the project chat on 21 November 2026. Accept
the timing-enabled Verilator 5.032 replay of the candidate as evidence
for the second-simulator gate. All 24 distinct positive Verilog
bench configurations passed at their frozen check counts.

The 67-job Icarus regression continues to cover the mutation checks
and D-016 trace comparisons. Kalash's source-review sign-off
remains pending before `rtl-freeze`.
[Verilator replay](../results/opt_area_timing.md#additional-simulator-replay) · [Freeze review](../reports/weekly_freeze_review.md)
