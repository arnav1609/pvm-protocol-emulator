# A programmable serial protocol emulator with a pin fabric and passive timing monitor

## Abstract

PVM is a reprogrammable ASIC that loads images over a dedicated SPI
port and executes serial transactions using a 32-word instruction
memory, a configurable pin fabric and a passive timing monitor. We ask
whether the fabric can reduce engine work at the pins, whether the
monitor can classify timing intervals without changing observed
protocol behavior, and whether the frozen device can implement a
protocol selected after the hardware freeze. In matched digital tests,
the arbitration guard used three issued instructions per regular bit
versus four for the engine check. The Manchester fabric reproduced the
same eight-bit waveform at 100 kbit/s with seven queued writes versus
16 direct pin writes. The monitor matched an integer oracle on 18
added boundary checks. A 29-word post-freeze DMX512 TX image produced
the required digital waveform on RTL and on the routed functional
netlist. The full variant routed at 50 MHz in an 8×4 IHP SG13CMOS5L
footprint with 30.9734% utilization and +3.180 ns slow-corner setup
slack. [Benchmark evidence](../evidence/v1.0_rc/benchmarks/) · [Routed reports](../results/v1.0_routed.md)

## Motivation and related work

A serial protocol block must meet pin timing while it branches on
inputs, handles data and reports faults. Creating a separate fixed
controller for each transaction makes it harder to reuse a small ASIC
for a protocol selected later. PVM asks how much of that work a compact
sequencer can do and what changes when pin logic and timing observation
have dedicated hardware.

The Raspberry Pi RP2040 PIO is a reference point for instruction-driven
I/O, with instruction memory, state machines, FIFOs and side-set. PVM
uses a dedicated SPI loader for image replacement on a Tiny Tapeout
design. Its experiment compares a shared engine and pin interface with
the fabric and monitor selectively included. The feature comparison
uses PVM builds and does not compare performance across chips.
[RP2040 datasheet, Chapter 3](https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf) · [PVM architecture](ARCHITECTURE.md)

## Architecture

The host asserts HALT, streams configuration and instruction bytes,
checks the device CRC, validates the image and reads the committed
image ID. It can preload the TX FIFO before ENABLE. During RUN the
engine executes 16-bit instructions for pin operations, branches,
waits, shifts, FIFO transfers and events. Dedicated output and
bidirectional pin behavior are defined by the same architecture
across all four builds. The pin guard selects the configured owner
and restores safe idle drive or releases the pins outside RUN.

The fabric combines four LUT4s, a counter, a holding register and an
open-drain arbitration guard. It can generate timed pin phases or
respond to a contention condition while the sequencer follows its
instruction schedule. The monitor evaluates eight rules over
synchronized pins, fabric signals or flags. It exposes verdict
counters and a four-entry log through SPI. [Architecture and pins](ARCHITECTURE.md) · [ISA](ISA.md) · [Fabric rules](../spec/05_FABRIC.md) · [Monitor rules](../spec/06_MONITOR.md)

## Experimental method

The digital workloads use the frozen commit
`b33a9227ac187f791a3733b94ac4e32879b10414` and a 50 MHz core clock.
F1 and F2 use image generation and SPI loading through the DUT.
F1 compares an engine-only check and a fabric-guard check using the
same eight released SDA bits. The idealized target can drive SDA
low after the second SCL rise. The sweep records six divider settings
for each configuration, with and without the injected collision.
F2 sends the same eight bits on both paths. It compares the sampled
output transitions to an expected sequence at 250 core clocks per
half-bit, using the first expected edge as the trace alignment point.
M1 tests minimum, maximum and clock-stretch cases against an integer
oracle with K=235 clocks and M=3 clocks. [Scripts and raw output](../evidence/v1.0_rc/benchmarks/)

For the physical comparison, A contains the engine, B adds the
fabric, C adds the monitor and D includes both. The four routed runs
use LibreLane 3.1.0.dev4, the pinned IHP SG13CMOS5L PDK, an 8×4
footprint and a 20 ns constraint. A, B and C build the freeze SHA
directly. D builds `752ebb97824cfd1161581497c22d3c171c4c6ca9`,
whose RTL and tape-out metadata match the freeze. [Variant inputs, raw metrics and run IDs](../results/v1.0_routed.md)

## Results

### F1 arbitration guard

In the regular released-one path, the fabric configuration uses three
issued instructions per bit. The engine comparison adds a JMP PIN
test, making four. Divider 4 was the fastest sampled setting that
produced all eight uncontended clocks and suppressed further clocks
after the injected collision in both configurations. The observed SCL
periods were 16 and 20 core clocks, or 3.125 and 2.5 MHz. The fabric
rate was 25% higher in this workload. Both paths suppressed further
SCL pulses after the injection at dividers 4, 8, 16 and 32. The fabric
latched ARB_LOST. At divider 2 the engine case still showed drive
at least four clocks after the injection, and the fabric stopped
early in the uncontended case.

A separate freeze test measured registered release two core clocks
after a qualified synchronized loss and four clocks after the pad
event with the SCL-high qualification satisfied. Earlier, the
qualifier could retain the prior high count when the current
synchronized SCL sample had fallen. D-001 now requires the current
sample to be high as well as a sufficient count. The owner's 360-case
decision sweep reported 30 mismatches before the change and zero at
the freeze SHA. The genuine-loss test preserved the specified release
timing. [F1 sweep](../evidence/v1.0_rc/benchmarks/f1-validated.log) · [Regression sweep](../evidence/v1.0_rc/benchmarks/arbitration_results_b33a922.txt) · [Fabric timing scope](../reports/S12_gate.md)

### F2 Manchester

Both paths matched the ten expected sampled transitions for the
eight-bit payload at 100 kbit/s. The fabric first emitted its
configured reset-zero bit. The engine supplied the remaining seven
bits with seven FAB writes. The direct implementation used 16 pin
writes for the eight bits. The fabric schedule also executed separate
SET Y instructions, so the write counts describe waveform servicing
in this schedule. The test observed the expected underrun when the
fabric was left without a next bit. [F2 edge and verdict log](../evidence/v1.0_rc/benchmarks/f2-manchester.log)

### M1 timing monitor

The direct MIN and MAX tests sampled 231, 232, 233, 237, 238 and
239 clocks around the two boundaries. All 12 comparisons matched
the oracle. Six clock-stretch boundary scenarios and 24 original
monitor component checks passed. A separate monitor on/off test
observed the same functional outputs for the tested stimulus and
detected a deliberate output perturbation. The owner also traced
the monitor output cone to the configuration read path. [M1 result log](../evidence/v1.0_rc/benchmarks/monitor-boundary.log) · [Monitor gate](../reports/S13_gate.md) · [Owner verification](../evidence/owner_b33a922/README.md)

### Physical cost

| Variant | Standard cells | Cell area (µm²) | Total and cell utilization | Slow setup slack (ns) | Worst hold slack (ns) |
| --- | ---: | ---: | ---: | ---: | ---: |
| A · Engine | 20,570 | 307,962 | 25.4899% | +7.254 | +0.109 |
| B · Engine and fabric | 21,547 | 329,588 | 27.2798% | +5.805 | +0.108 |
| C · Engine and monitor | 23,069 | 351,585 | 29.1006% | +5.746 | +0.109 |
| D · Full design | 24,863 | 374,213 | 30.9734% | +3.180 | +0.108 |

Total utilization and standard-cell utilization agree in these builds.
D adds 66,251 µm² of standard-cell area, or 21.5%, relative to A.
D met the project limits of 40% utilization and +1.0 ns slow-corner
setup slack. Static setup and hold passed at the slow, typical and
fast corners with zero total negative slack. D also passed all
ten Tiny Tapeout prechecks and the CI gate-level smoke test.
[Routed comparison and raw reports](../results/v1.0_routed.md)

## Held-out protocol

After the public freeze tag resolved to the approved SHA, Codex used
one Python `secrets.randbelow(5)` sample on the ordered pool
1-Wire, SWD, WS2812, PS/2 RX and DMX512 TX. Index 4 selected DMX512 TX.
The team already had separate pre-freeze fit studies for a 19-word
1-Wire transaction and a 32-word initialized SWD read. DMX512 TX had
no pre-freeze fit program in that study.

The selected 29-word image loaded over SPI and sent two short packets
per run. Each packet had a 128 µs BREAK, 16 µs mark after BREAK,
4 µs bit cells, one 0x00 start code and 24 data slots containing 0xA5.
The independent decoder accepted the initial and reloaded RTL
captures and rejected the mutant with an 8 µs first mark after BREAK.
The zero-delay routed gate replay matched both accepted P5 captures
cycle for cycle. [Recorded draw](../results/held_out_draw.md) · [Fit-study scope](../results/fit_study.md) · [Image, capture and contract](DMX512_TX_DEMO.md) · [Routed replay](../results/v1.0_routed.md)

## Verification and limitations

The freeze evidence includes 71 accepted registered jobs, 52 seeded
Verilator replays and scoped bounded safety checks. The instruction-set
simulator matched 13,848 cycles for the three baseline demos and
7,680 cycles for five directed stall, branch, FIFO and shift scenarios.
UART, SPI, I²C and DMX512 passed functional gate replay at their
checked pins. The slow-corner delay replay was inconclusive after
unsupported timing checks and a timeout. [Verification scope](VERIFICATION.md) · [Owner fault and proof records](../evidence/owner_b33a922/README.md)

The digital target models fix assumptions about sampling and edge
behavior. The original SWD model advanced the target after falling
edges and masked a parity bug. Under corrected rising-edge behavior,
the original program rejected a valid even-parity response. The
corrected 32-word program checks parity before advancing the target.
Heet separately reviewed the 1-Wire and SWD models. The 1-Wire
pull-up is idealized, and a delayed digital high in Heet’s sensitivity
check changed the captured bit. The fit studies cover the stated
transactions. [Fit-study model correction and review](../results/fit_study.md)

The F1 rates apply to an ideal simulated workload. The F2 result
uses one payload and schedule. M1 measures synchronized digital
intervals with controlled phase. The monitor traceability audit retains
an open pad-phase precision claim. Board tests, electrical compliance,
silicon performance and power remain open. The authorization candidate
has its own trust-hardware and physical qualification work.

The expanded matrix's seven new rows have author-side RTL and
mutation evidence. Heet's independent target-model acceptance,
five-rule ISS spot-check and final claim audit are pending. The
tutorial records the example's simulated pulse timing. A newcomer's
completion time awaits Heet's trial.
[Pending independent checks](SUBMISSION_WRITEUP.md#independent-checks-pending)

## Conclusion

Dedicated pin hardware reduced instruction or write work in the F1
and F2 workloads. The monitor reproduced the expected boundary
decisions for the tested intervals. The full build retained positive
static timing slack at 50 MHz, and the post-freeze DMX512 image
demonstrated a new transaction within the fixed 32-word architecture.

## Reproduction appendix

Run the source regression on the full release SHA with Icarus 12.0
and cocotb 2.0.1. Regenerate the golden CSVs with full Git history and
LF checkout. Build the DMX512 image and compare its serialized bytes.
Run F1, F2 and M1 on the pinned freeze SHA with the archived scripts.
Verify the routed ZIP and its internal manifest, then use the packaged
Icarus 13.0 recipe for functional gate replay. The four variant run
IDs, PDK revision, metrics and hardware checksums anchor the physical
comparison. [Fresh-clone recipe](RELEASE_CHECKLIST.md) · [Benchmark scripts](../evidence/v1.0_rc/benchmarks/) · [Physical commands and artifacts](../results/v1.0_routed.md) · [AI and tool disclosure](AI_USE.md)
