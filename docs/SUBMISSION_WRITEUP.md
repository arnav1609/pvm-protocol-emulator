# Submission write-up outline

## Design and demos

Open with the problem PVM solves and the distinction between the
programmable engine, fabric and passive monitor. Include the SPI
image-loading sequence and pin mapping, then show each demo with the
image-build command, TX input, expected waveform and evidence link.
The existing UART, SPI and I²C waveforms belong here.
[Architecture](ARCHITECTURE.md) · [S14b evidence](../reports/S14b_protocols_gate.md)

## Experiments

Use versioned image sources, an exact RTL commit, the same clock and
target constraints, and repeatable commands for every result.
Record event cycles alongside the waveform and publish raw measurements.

| Experiment | Comparison and measures |
| --- | --- |
| F1 · I²C arbitration | Run matched collision scenarios with an engine-only arbitration check and the fabric guard. Measure instructions per bit, maximum SCL rate and worst-case cycles from observed loss to blocked drive. |
| F2 · Manchester | Compare software-timed output against counter-driven output. Measure transition timing, data bit rate and engine ticks spent servicing the waveform. Exercise simultaneous writes and output boundaries in the holding path. |
| M1 · Timing monitor | Replay the same events with the monitor disabled and enabled. Check output equivalence and compare logged min/max verdicts at and around the configured tolerance limits. |
| A/B/C/D · area and timing | Record variant, defines, PDK revision, clock and flow. Use matched reports for utilization, cell area, setup and hold. Current A/B/C area values are mapped synthesis estimates. Only D has a routed result so far. |
| Held-out protocol | Record the independent draw before writing the program. Preserve the selected protocol requirements, load the image over SPI and record the checked pin behavior and any constraints encountered. |

[Fabric specification](../spec/05_FABRIC.md) · [Monitor specification](../spec/06_MONITOR.md) · [Project decisions](../spec/DECISIONS.md)

## Evidence to finish

| Target | Deliverable |
| --- | --- |
| RTL freeze review | Kalash runs XSim and reviews S12–S14b. The physical gate passed. Record the independent review sign-off before tagging. |
| 13 December 2026 | Review this outline and assign each section. Confirm the tool and AI disclosure, including Claude’s role. |
| 18 December 2026 | Record F1, F2 and M1 measurements and the held-out demo. |
| 20 December 2026 | Assemble the first write-up drafts with reproducible commands and evidence links. |
| 4 January 2027 | G3 on the final candidate. Record GDS, precheck, gate-level smoke and demo replay for the commit that will be tagged. |
| 13 January 2027 | Verify public access and a fresh-clone run of the guide and demos. |
| 16 January 2027 | Internal target to submit via the competition form. Add the optional demo video if ready. |

Record the independent ISS comparison and Heet’s verification results
when evidence is ready. In the submission, distinguish simulation,
routed timing and board or silicon results.
[Heet’s verification handover](verification_handoff.md) · [Competition rules](https://blog.janestreet.com/protocol-emulator-asic-competition/#submission-and-judging)
