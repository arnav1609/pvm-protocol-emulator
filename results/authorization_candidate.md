# PVM authenticated load candidate

The authorization feature is integrated into the trusted-input PVM
top on `codex/pvm-authorized-load`. The synthesizable files used for
the matched mapping come from
`df35afed2cbe2c12cc97caa54029f81b78ac6d87`. The approved 8×4 target,
50 MHz target and original pin assignments are retained in the
project metadata. The authorization-only utilization exception covers
both the 40% cap and the 33.7187% comparison target.

The physical sign-off is blocked at the trust boundary. The current
Tiny Tapeout wrapper provides no reviewed device-secret or reset-fresh
challenge source. Its secure configuration therefore stays locked.
The useful simulation and mapping top accepts controlled trusted
inputs. A functional secure GDS, precheck, routed timing, and
activity-based power comparison require the provider to be implemented
and integrated. The verified v1.0 candidate remains the submission
fallback. [Trust provisioning design](../docs/AUTHORIZATION.md#trust-provisioning-design) · [Verified baseline](https://github.com/arnav1609/pvm-protocol-emulator/tree/codex/pvm-v1.0-rc)

## Whole-core area comparison

These are matched pre-route IHP standard-cell maps with Yosys 0.52,
Berkeley ABC and the pinned CMOS5L typical libraries. The two secure
maps include the dispatcher, full retained SUBMIT, INFO snapshot,
canonical checks, guarded bus and all original PVM subsystems.
The maps include the logic consuming the trusted inputs. Physical key
storage and challenge generation are still open.

| Variant | Standard cells | Standard cell area (µm²) | SRAM area (µm²) | Total (µm²) |
| --- | ---: | ---: | ---: | ---: |
| Frozen PVM | 16,441 | 304,578.5 | 0 | 304,578.5 |
| Integrated inferred memory | 45,018 | 824,839.4 | 0 | 824,839.4 |
| Integrated IHP SRAM | 39,602 | 696,959.3 | 50,489.1 | 747,448.4 |

Including the macro, SRAM saved 77,391.0 µm² (9.4%) relative to the
inferred-memory secure top. The integrated SRAM map adds 442,869.9 µm²
relative to the matched frozen map. The 158,221 µm² result in the
handoff covers the SRAM-backed hash block alone. These numbers
account for logic and macro area before floorplanning, routing, CTS
and a physical trust provider.

[Raw mapping results and netlist hashes](../evidence/authorization/) · [Reproduction commands](../docs/AUTHORIZATION.md#reproduce)

## Handoff checks

The supplied block suites completed on both inferred memory and the
IHP functional SRAM models. Each passed 42 digest tests and 23 signed
DMX SPI frames, including the malformed, truncated, bad-tag and
missing-trust rejection cases. The records suite accepted all 20
canonical DMX chunks. The SPI shifter overlay passed all 71 legacy
registry jobs with the original interface. The integrated signer
reproduced the reference 23 DMX frames byte for byte. The authorizer's
host tests cover separate START confirmation and receipts from an
unrelated challenge.

## Secure RTL replay

The SRAM-backed integrated RTL passed the following real-SPI tests at
core/SCK clocks of 50 MHz/3.125 MHz in simulation. All signatures used
public fixture keys and fresh test challenges.

| Case | Verified result |
| --- | --- |
| UART | Owner-only START, byte 0x35 at the frozen 8N1 bit timing, native DONE |
| SPI | Mode 0, bytes 0xA6 and 0xC9, exact high and low clock periods, native DONE |
| I²C | Address 0x50 and data 0x3C, open drain, both ACKs, target clock stretch, native DONE |
| DMX512 | Two authorized loads, 159 exact programming writes per load, 392 frozen P5 transitions per run, native DONE |
| DMX512 alignment and mutant | First BREAK 602 clocks after ENABLE in the frozen and secure tests. Short MAB compiled into a correctly authenticated image and rejected at the waveform check. |
| Authorization | 63 INFO verdicts checked, all 11 identities, head cancellation, busy replay, malformed and altered frames, stale sessions, reset during a command, correct MAC with wrong link or reserved address, wrong image CRC |
| FIFO and revocation | 40 INFO verdicts checked, TX and RX shortages retry without a sequence increment, safe read cannot pop RX, authenticated RX byte is cached with one ACK, four ordered TX writes, safe stop on trust loss |
| Guard mutations | Reject checks detect bypassed tag, link and frame-alignment logic |

The UART test starts its observation after the same short post-ENABLE
window that the legacy host provided. It retains the original start,
data and stop bit checks. The frozen UART, SPI and I²C benches still pass
through the baseline decoder.

An accepted four-byte TX push took 46,511 core clocks from the start of
the SPI frame through the last write, including 33,565 clocks from the
end of the frame. At the simulated 50 MHz this gives an upper bound of
about 4.3 kB/s with serialized commands, before INFO polling and any
retry. A sustained hardware streaming measurement remains open. The four
demo images use preloaded data or generate their output internally, so
their pin timing does not depend on runtime host FIFO service.

[RTL replay logs and signed vectors](../evidence/authorization/rtl/) · [Guard checks](../evidence/authorization/guards/) · [Desktop host tests](../evidence/authorization/host_tests.log)

## SRAM mapped-netlist replay

UART, SPI, I²C and both DMX runs passed on the exact mapped SRAM
netlist. The replay used the 27 standard-cell functions generated from
the same pinned Liberty used for mapping, the pinned IHP SRAM models,
and zero-delay Verilator. Assertions checked the real SPI frames and
pin waveforms. The runner also compared every configuration bus write
with the image builder's expected address and byte. The two DMX
sessions each reproduced the 392-transition frozen trace.

The mapped SRAM netlist SHA-256 is
`d6c9d3285f441e800894165b22f68de84f0c7cdb30bc6253669fc00bba1e06a3`.
[Mapped replay logs](../evidence/authorization/mapped_replays/) · [Netlist checksums](../evidence/authorization/mapped_netlists.sha256)

Icarus 13.0 also passed the mapped GUARDS replay using the original
IHP functional standard-cell and SRAM models. That replay checked partial
SPI frames, altered tags, a replayed sequence and a valid MAC with a
wrong image link on the same netlist.

The independently launched mapped DMX reload passed on the same
compiled model. The queued duplicate was stopped after that result.
The subsequent mapped short-MAB case authenticated all 159 programming
writes and failed the expected `DMX_MAB_MIN` waveform check.
