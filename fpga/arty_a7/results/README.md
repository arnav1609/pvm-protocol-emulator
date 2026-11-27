# Artix-7 implementation and board results

The Arty A7-100T bench passed all five USB readbacks and all six ILA
comparisons using the original `JANE_STREET.xpr` build. The core uses the
16 frozen RTL files at `b33a9227ac187f791a3733b94ac4e32879b10414`. The FPGA
integration adds a wrapper, UART-to-SPI bridge, I²C fixture, board
constraints and ILA. The routed ASIC release evidence is tracked separately.
[Board guide](../README.md) · [ASIC routed release](../../../results/v1.0_routed.md)

## Vivado implementation

| Metric | Result |
| --- | --- |
| Tool and part | Vivado 2024.1 (build 5076996), `xc7a100tcsg324-1` |
| Clock | 100 MHz board oscillator, 50 MHz generated core and ILA clock |
| Routed setup and hold | +3.814 ns worst setup slack, +0.028 ns worst hold slack, zero failing endpoints and zero unconstrained internal endpoints |
| Logic utilization | 5,237 / 63,400 slice LUTs (8.26%), 4,567 / 126,800 registers (3.60%) |
| Block RAM and I/O | 96 / 135 block RAM tiles (71.11%), 35 / 210 bonded IOBs (16.67%) |
| Routing | 9,520 / 9,520 routable nets routed, zero routing errors |
| DRC | Five warnings across configuration-voltage metadata and generated debug logic. CFGBVS-1 (1), PDCN-1569 (3), RTSTAT-10 (1). Zero DRC errors. |
| Power evidence | Vivado generated a low-confidence estimate with no simulation activity file. A validated power value remains open. |

Utilization includes the FPGA wrapper and analyzer. The report hashes in
[implementation provenance](implementation.sha256) identify the exact
Vivado outputs used for the table. [Build input hashes](build_inputs.sha256)

## FPGA-measured (Artix-7)

The bench used the J10 USB data cable with SW0 high, the J3 onboard pull-ups
and target, and no peripherals on J3 or the Pmod headers. Each trigger
captured one 131,072-sample window at 50 MHz. READY was `0x42` and DONE was
`0x44` in each of the five runs. The terminal status, fault PC, FIFO,
flags, image ID and monitor fields matched the archived readback contract.
[USB readbacks](readback.jsonl) · [Host log](host.log) · [Waveform checks](comparisons.log)

| ILA capture | Result |
| --- | --- |
| Host reset | Active low for 50 core clocks (1 µs), then released high |
| UART TX | `0x35`, LSB-first 8N1, 434 core clocks per bit |
| SPI mode 0 | `A6 C9` MSB first at the 16 rising SCK edges |
| I²C write | `START A0 ACK 3C ACK STOP`. First ACK SCL low for 412 core clocks (8.24 µs). The direction probes confirmed open-drain behavior and SDA release during ACK. |
| DMX512 initial load | Two logic-level packets, each with 25 slots, a 128 µs BREAK, a 16 µs MAB and 4 µs bit cells |
| DMX512 reload | Same result after reloading the image. The two separately triggered CSV captures were byte-identical. |

I²C evidence covers the onboard fixture. DMX512 evidence covers FPGA
logic-level signaling. External-device interoperability, EEPROM readback
and the RS-485 physical layer remain outside this run.

The raw ILA CSVs, timing, utilization, routing and DRC reports, bitstream
and probes are preserved in the original handoff archive `PVM_FPGA_A1_Arnav_Handoff.zip`. The saved
capture manifest records the raw file identities.
[Capture hashes](SHA256SUMS.txt) · [Implementation and archive hashes](implementation.sha256)
