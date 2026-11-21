# 02 Pins and top level

## Tiny Tapeout wrapper ports (fixed by the template - do not change)
```verilog
module tt_um_<githubuser>_pvm (
    input  wire [7:0] ui_in,    // dedicated inputs
    output wire [7:0] uo_out,   // dedicated outputs
    input  wire [7:0] uio_in,   // bidirectional: input path
    output wire [7:0] uio_out,  // bidirectional: output path
    output wire [7:0] uio_oe,   // bidirectional: 1 = output enabled
    input  wire       ena,      // always 1 when design is selected; may be ignored
    input  wire       clk,
    input  wire       rst_n     // active low reset
);
```
The owner fills `<githubuser>`. Until then use `tt_um_pvm` as placeholder in tests and keep the name in ONE place (`src/project.v`).

## Host pins (fixed)
| Pin | Signal | Direction |
|---|---|---|
| ui_in[0] | SPI SCK from host | in |
| ui_in[1] | SPI CS_n from host (active low) | in |
| ui_in[2] | SPI MOSI from host | in |
| uo_out[7] | SPI MISO to host | out |

## Protocol pins: 20, indexed P0..P19
| Index | Physical | Capability |
|---|---|---|
| P0..P4 | ui_in[3..7] (P0 = ui_in[3]) | input only |
| P5..P11 | uo_out[0..6] (P5 = uo_out[0]) | output only, push-pull, never Hi-Z |
| P12..P19 | uio[0..7] (P12 = uio[0]) | bidirectional; the only pins allowed open-drain |

### Pin input vector `pin_in[19:0]` (used by engine, fabric, monitor)
- P0..P4: `ui_in[7:3]` after 2-flop synchroniser.
- P5..P11: the **final driven value** of that uo pin (internal read-back, registered once so it aligns with synchronised inputs: 2-cycle delay matched).
- P12..P19: `uio_in[7:0]` after 2-flop synchroniser.

Host and protocol input pins pass through `pvm_sync2` exactly once, in `pvm_top`. Modules never synchronise them again.

The reset pin uses its own two-flop release synchronizer in `pvm_top`.
The core reset asserts asynchronously and releases just after the second
rising clock edge after external reset release. The registered reset
consumers resume on the next rising edge. [D-017 reset contract](rev/PVM-IF-D017-RESET-RELEASE.md)

## Output rule summary (detail in 05/07)
- `uo_out[7]` = MISO from host interface.
- `uo_out[6:0]` = P11..P5 values from pin_guard (never Hi-Z; idle level when not driven).
- `uio_out[7:0]`, `uio_oe[7:0]` = P19..P12 from pin_guard.
- On reset, HALT, FAULT, DONE and when the engine is not RUN: `uio_oe = 8'h00`, `uo_out[6:0]` = each pin's configured idle level (reset value of idle level = 0).

## Top-level hierarchy (built in stage 12)
```
tt_um_<user>_pvm (src/project.v)
 `-- pvm_top
      |-- pvm_sync2 x (3 host + 5 ui + 8 uio)
      |-- pvm_hostif      SPI target -> byte bus master
      |-- pvm_cfg         lifecycle FSM, CRC, validation, CTRL/STATUS/FAULT, bus decode
      |-- pvm_imem        32 x 16 + valid
      |-- pvm_engine      PIO-style SM (uses pvm_fifo x2, pvm_tick)
      |-- pvm_fabric      4 LUT4, counter, Manchester hold, ARB guard
      |-- pvm_mon         SPECMON
      `-- pvm_pin_guard   per-pin ownership and safety
```
