# Submission write-up outline

## Design and demos

Open with the problem PVM solves and the distinction between the
programmable engine, fabric and passive monitor. Include the SPI
image-loading sequence and pin mapping, then show each demo with the
image-build command, TX input, expected waveform and evidence link.
Include the held-out DMX512 TX waveform and its one-time draw.
[Architecture](ARCHITECTURE.md) · [S14b evidence](../reports/S14b_protocols_gate.md) · [DMX512 TX](DMX512_TX_DEMO.md) · [Draw record](../results/held_out_draw.md)

## Experiments

Use versioned image sources, an exact RTL commit, the same clock and
target constraints, and repeatable commands for every result.
Record event cycles alongside the waveform and publish raw measurements.

| Experiment | Comparison and measures |
| --- | --- |
| F1 · I²C arbitration | Run matched collision scenarios with an engine-only arbitration check and the fabric guard. Measure instructions per bit, maximum SCL rate and worst-case cycles from observed loss to blocked drive. |
| F2 · Manchester | Compare software-timed output against counter-driven output. Measure transition timing, data bit rate and engine ticks spent servicing the waveform. Exercise simultaneous writes and output boundaries in the holding path. |
| M1 · Timing monitor | Replay the same events with the monitor disabled and enabled. Check output equivalence and compare logged min/max verdicts at and around the configured tolerance limits. |
| A/B/C/D · area and timing | Record variant, defines, PDK revision, clock and flow. Use matched reports for utilization, cell area, setup and hold. Use the matched routed comparison with one 8×4 footprint and 50 MHz target. |
| Held-out protocol | Cite the recorded post-freeze draw before presenting the image results. Preserve the selected protocol requirements, load the image over SPI and record the checked pin behavior and any constraints encountered. |

[Fabric specification](../spec/05_FABRIC.md) · [Monitor specification](../spec/06_MONITOR.md) · [Project decisions](../spec/DECISIONS.md)

## Release milestones

| Target | Deliverable |
| --- | --- |
| 13 December 2026 | Baseline and held-out demo images with load instructions and waveform evidence. |
| 24 December 2026 | Final routed build ready for gate-level replay, with GDS, precheck, netlist hash and timing. |
| 31 December 2026 | Public v1.0 and write-up ready after owner review and a fresh-clone check. |

Describe the ISS comparison and owner verification within their
recorded scope. Keep F1, F2 and M1 claims tied to measured results.
Treat RTL simulation, functional gate replay, routed timing and board
results as separate evidence.
[Release checklist](RELEASE_CHECKLIST.md) · [Owner verification](../evidence/owner_b33a922/README.md) · [Competition rules](https://blog.janestreet.com/protocol-emulator-asic-competition/#submission-and-judging)
