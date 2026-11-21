# PVM v2.1 instruction set

PVM uses 32 addressed 16-bit words. Bits 15–13 select the operation,
bits 12–8 encode delay and side-set, and bits 7–0 hold the operand.
SIDE_CNT reserves the top zero, one or two bits of the delay/side-set
field. The remaining bits encode 0–31, 0–15 or 0–7 extra ticks.
[Encoding and complete operand tables](../spec/04_ISA.md)

| Opcode | Assembly examples | Function |
| --- | --- | --- |
| 0 | `jmp again`, `jmp x--, again` | Conditional or unconditional branch |
| 1 | `wait 1, pin, 13 side 1` | Wait for a pin, fabric output or flag |
| 2 | `in pins, 8` | Shift data into ISR |
| 3 | `out pins, 1`, `out exec, 16` | Shift OSR data to a selected destination |
| 4 | `push iffull block`, `pull` | Transfer data between shift registers and FIFOs |
| 5 | `mov x, ~y`, `mov exec, x` | Move, invert or reverse a source value |
| 6 | `evt done` | Signal a lifecycle event or update a flag |
| 7 | `set pins, 0 [1]` | Write a small immediate to a selected destination |

The assembler supports labels, `.org`, `.word`, `#` and `//` comments.
Bare PUSH and PULL are blocking. An omitted side-set value is zero
when side-set is enabled. The assembler takes `--side-count` for a
standalone hex listing. The image builder derives it from SIDE_CNT.
[Assembler and image commands](TOOLCHAIN.md)

## Timing

- Instructions issue on engine ticks, which are separated by CLKDIV
  core clocks. A delay runs after the instruction completes. Side-set
  takes effect on issue, including when the instruction stalls.
- A taken branch loads its target. Otherwise the PC advances after
  completion and delay, with configured wrap at WRAP_TOP.
- OSR starts empty with a shift count of 16. A WIDE transfer waits
  for both bytes or slots, then transfers low byte and high byte on
  consecutive ticks. Its delay starts on the high-byte tick.
- EXEC schedules the injected word after the parent’s delay.
  Injected WAIT and blocking transfers can stall, with ordinary
  timeout behavior. A nested EXEC raises ILLEGAL_OP. An injected
  fault reports the parent’s PC.

Use the frozen ISA spec for exact semantics, and the decision log for
the recorded clarifications. [ISA](../spec/04_ISA.md) · [Decisions](../spec/DECISIONS.md)
