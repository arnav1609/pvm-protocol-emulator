# PVM ISA reference card

**32 × 16-bit words** · `[15:13] opcode` · `[12:8] side/delay` · `[7:0] operand`
One instruction per line. Optional suffix `side N [D]` defaults both values to zero. Labels, `.org`, `.word`, `#` and `//` comments are supported.

| Op | Example | Effect |
| --- | --- | --- |
| 0 JMP | `jmp x--, loop` | Branch on the selected condition. A bare target is unconditional. |
| 1 WAIT | `wait 1 pin 13 side 1` | Stall until pin, fabric output or flag equals 0 or 1. |
| 2 IN | `in pins, 8` | Shift source bits into ISR. Direction comes from `IN_SHR`. |
| 3 OUT | `out pins, 1` | Shift OSR bits to a destination. Direction comes from `OUT_SHR`. |
| 4 PUSH/PULL | `push iffull block`, `pull ifempty noblock` | ISR → RX or TX → OSR. Default is blocking. |
| 5 MOV | `mov x, ~y`, `mov isr, ::x` | Copy, invert (`~`) or reverse 16 bits (`::`). |
| 6 EVT | `evt set 2`, `evt clr 2`, `evt done` | Set/clear a flag or finish and return outputs to idle. |
| 7 SET | `set pins, 1 [4]` | Write a 5-bit immediate to pins, X/Y, pindirs or fabric. |

**Branch conditions** · `always`, `!x`, `x--`, `!y`, `y--`, `x!=y`, `pin`, `!osre`.
X/Y decrement even at zero. The branch condition uses the old value.

**Ticks** · At 50 MHz, one tick is `20 ns × max(1, CLKDIV)`. A completed instruction uses its completion tick plus `D` extra ticks. Side-set applies on issue, even during a stall. The high 0, 1 or 2 bits of the side/delay field are side-set. Max delay is 31, 15 or 7, respectively.

**Shifts and FIFO** · An encoded count of 0 means 16. OSR starts empty with shift count 16. WIDE transfers require both bytes or slots before touching either FIFO, then transfer low and high bytes on consecutive ticks. The delay starts at completion on the second tick.

**PC and EXEC** · ENABLE starts at `ENTRY_PC`. Fall-through wraps at `WRAP_TOP` to `WRAP_BOTTOM`. EXEC issues the injected word after the parent's delay. A nested EXEC faults at the parent PC.

**Pins** · P0–P4 input. P5–P11 dedicated output. P12–P19 bidirectional. Set the pin's owner and mode in `PIN_CFG` as well as the instruction's base/count. Open-drain output drives low or releases.

[Complete encoding and timing](../spec/04_ISA.md) · [Register map](../spec/03_BUS_AND_REGMAP.md) · [Worked protocol tutorial](ADD_A_PROTOCOL.md)
