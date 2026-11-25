# PVM competition write-up

PVM emulates serial transactions from programs loaded over a dedicated
SPI host interface. It combines a 32-word instruction engine, a pin
fabric for timed output and open-drain arbitration, and a passive
monitor that records timing verdicts. The host verifies the image
CRC and committed ID before starting the program. Changing protocols
means loading a different image. [Architecture](ARCHITECTURE.md) · [ISA](ISA.md) · [Toolchain and host loader](TOOLCHAIN.md)

## Protocol demos

| Demo | Checked behavior |
| --- | --- |
| UART TX | 0x35 as 8N1 at 434 core clocks per bit on P5 |
| SPI mode 0 | Transfers 0xA6 and 0xC9 MSB first with 16 rising SCK edges |
| I²C write | Open-drain write to address 0x50 and data 0x3C with two ACKs and target clock stretching |
| DMX512 TX | Two 25-slot packets per run and matching initial and reloaded captures |

All four demos passed at the simulated pins after SPI image loading.
The frozen RTL regression accepted 71 jobs. A 52-run seeded Verilator
replay and directed ISS comparisons add independent checks within
their recorded scope. The full routed netlist passed the four demo
replays using zero-delay functional models. All three static timing
corners passed. Slow-corner delay simulation was inconclusive.
[Baseline pin checks](../reports/S14b_protocols_gate.md) · [Verification](VERIFICATION.md) · [Routed evidence](../results/v1.0_routed.md)

[Frozen protocol coverage matrix](PROTOCOL_MATRIX.md)

## Held-out draw and result

The hardware freeze preceded one uniform draw from 1-Wire, SWD,
WS2812, PS/2 RX and DMX512 TX. Codex recorded the freeze SHA, pool,
time and sampled index 4. The team had already tested the fit of
specific 1-Wire and SWD transactions. The selected DMX512 TX image
used 29 of 32 words. It produced 128 µs BREAK, 16 µs mark after
BREAK, 4 µs bit cells, and one 0x00 start code plus 24 0xA5 data
slots per packet. The owner decoder caught an 8 µs first mark
after BREAK in the mutation run. [Draw](../results/held_out_draw.md) · [Fit studies](../results/fit_study.md) · [DMX512 image and waveform](DMX512_TX_DEMO.md)

## What the fabric and monitor add

- **Arbitration.** The fabric guard used three instructions per regular bit versus four for the engine-only check in the released-one workload. At the fastest passing tested divider, the SCL periods were 16 and 20 core clocks. The 25% rate difference applies to the ideal digital workload. The separate qualified-loss test measured registered release two clocks after synchronized observation and four after the pad event. [F1 evidence](../evidence/v1.0_rc/benchmarks/f1-validated.log)
- **Manchester.** Both paths matched the eight-bit waveform at 100 kbit/s. The engine made seven FAB writes after the reset-zero bit or 16 direct pin writes. The fabric case also included separate SET Y instructions. [F2 evidence](../evidence/v1.0_rc/benchmarks/f2-manchester.log)
- **Timing verdicts.** The monitor agreed with the integer oracle on 12 direct boundaries and six clock-stretch cases. The on/off test observed identical functional outputs in its tested workload and detected an intentional perturbation. [M1 evidence](../evidence/v1.0_rc/benchmarks/monitor-boundary.log) · [Monitor gate](../reports/S13_gate.md)

The four variants routed under matched 8×4 and 50 MHz constraints.
The full design used 30.9734% overall and standard-cell utilization.
At 50 MHz it had +3.180 ns slow-corner setup slack and +0.108 ns
worst hold slack. It passed GDS, gate-level smoke and 10/10 prechecks.
Board behavior, silicon power and electrical compliance remain
outside the measured results. [Matched measurements and run IDs](../results/v1.0_routed.md)

## Toolchain and release evidence

The assembler follows the 32-word ISA and emits addressed 16-bit
words. The image builder combines them with register configuration,
CRC and TX preload. The SPI loader validates and reads back the
committed image ID before enabling the engine. The ISS implements
the published execution rules and has a stated directed cycle
denominator. [ISA](ISA.md) · [Toolchain and host guide](TOOLCHAIN.md) · [ISS provenance](ISS_PROVENANCE.md)

The full routed variant is traceable to a source SHA, a netlist
hash, and one Tiny Tapeout run. Use Icarus 13.0 or later for functional
gate replay with the pinned IHP models. Icarus 12.0 leaves timing-check
outputs undriven in those models, which prevents reset from reaching
the mapped flip-flops. Seven scoped safety families support the
formal checks described in the verification evidence. The optional
Artix-7 real-wire run remains pending. The authorization feature
has a separate go/no-go and no claim in the verified baseline.
[Routed evidence](../results/v1.0_routed.md) · [Version requirement](../results/gate_icarus.md) · [Authorization decision brief](../results/authorization_decision.md)

## Reproduce the submission

Use the release checklist for exact commits, simulator versions,
golden traces, rebuilt images and routed replay. The manuscript
gives the methods, raw evidence and limits for each claim.
[Release checklist](RELEASE_CHECKLIST.md) · [Full manuscript](MANUSCRIPT.md) · [AI and tool disclosure](AI_USE.md)
