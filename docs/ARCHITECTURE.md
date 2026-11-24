# PVM architecture

PVM v2.1 uses a 50 MHz core clock in the routed variant. The host
programs and interrogates it over a separate mode 0 SPI interface.
The protocol itself runs from on-chip state once the image is enabled.

| Block | Function |
| --- | --- |
| Host interface | Converts the SPI byte stream to addressed register accesses. At 50 MHz, host SCK may run up to 3.125 MHz. |
| Configuration and lifecycle | Keeps a running CRC of accepted image bytes, validates configuration and commits the image ID. Only a committed image in READY can enter RUN. HALT opens a new loading session and clears the FIFOs and sticky status flags. |
| Instruction memory and engine | A 32×16-bit instruction RAM with valid bits feeds the engine. The engine sequences pins, waits, branches and two four-entry byte FIFOs. Its tick rate is set by CLKDIV. |
| Fabric | Four configurable LUT4s form a feed-forward logic network. A counter and a holding register support Manchester output. An open-drain arbitration guard can release SDA and SCL after detecting contention. |
| Monitor | Eight rules read synchronized pin, fabric and flag events. The monitor exposes counters and a four-entry log through the host read path. |
| Pin guard | Selects the configured pin owner and enforces drive mode. Outside RUN, bidirectional pins are released and dedicated outputs take their configured idle levels. |

The host loads instruction and configuration bytes in a defined order,
checks CRC_CALC, writes CRC_EXPECT, requests VALIDATE and verifies the
committed image ID. TX bytes may be preloaded after HALT and before
ENABLE. [Register map](../spec/03_BUS_AND_REGMAP.md) · [Lifecycle](../spec/07_FAULTS_LIFECYCLE.md)

## Pins

| Use | Tiny Tapeout signal |
| --- | --- |
| Host SCK, CS_n and MOSI | `ui_in[0]`, `ui_in[1]` and `ui_in[2]` |
| Host MISO | `uo_out[7]` |
| P0–P4, input only | `ui_in[7:3]` in ascending pin order |
| P5–P11, output only | `uo_out[6:0]` in ascending pin order |
| P12–P19, bidirectional with optional open drain | `uio[7:0]` in ascending pin order |

External inputs are synchronized at the top level. Programmed outputs
pass through the pin guard and an output register.
[Pin specification](../spec/02_PINS_AND_TOP.md) · [Fabric](../spec/05_FABRIC.md) · [Monitor](../spec/06_MONITOR.md)

## Comparison variants

| Variant | Included blocks | Build defines |
| --- | --- | --- |
| A | Engine | `PVM_NO_FABRIC` and `PVM_NO_MON` |
| B | Engine and fabric | `PVM_NO_MON` |
| C | Engine and monitor | `PVM_NO_FABRIC` |
| D | Engine, fabric and monitor | Default |

The host interface, pin mapping and instruction set are shared. The
release campaign routed all four variants with the same 8×4 footprint
and 50 MHz constraint. [Matched area and timing evidence](../results/v1.0_routed.md)
