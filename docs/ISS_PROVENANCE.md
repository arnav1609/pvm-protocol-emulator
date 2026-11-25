# PVM instruction-set simulator provenance

Codex wrote the initial instruction-set simulator for Arnav's toolchain
in `afcc798e8b237cae08ae594e0a8cbbfdcd045849`. The model uses the register
and opcode definitions in spec 03 and the execution rules in spec 04
plus D-013 to D-015. It implements those contracts in Python. The
corresponding RTL is used in the separate lockstep harness, which
feeds synchronized inputs and compares observable engine state and
effects at each sampled cycle.
[Initial model](https://github.com/arnav1609/pvm-protocol-emulator/blob/afcc798e8b237cae08ae594e0a8cbbfdcd045849/tools/pvm_iss.py) · [ISA specification](../spec/04_ISA.md) · [Register map](../spec/03_BUS_AND_REGMAP.md) · [Decision record](../spec/DECISIONS.md)

The recorded denominator is 13,848 core cycles across UART, SPI and
I²C, plus 7,680 core cycles across five directed scenarios covering
WAIT, branching, FIFO boundaries and shifts. They are two separately
measured campaigns. Pin-waveform checks run alongside the three
baseline engine comparisons. DMX512 has RTL and functional gate
waveform evidence. Its ISS comparison and randomized legal-image
coverage remain open. [Trace counts and signal scope](VERIFICATION.md)

## Five rules for Heet to spot-check

Check the expected rule against spec 04 and the decision log independently,
before opening the Python implementation. Record the spec clause, a directed
input and expected per-tick result, and any discrepancy.

| Rule | Spot-check case | Expected result |
| --- | --- | --- |
| ENABLE and OSR empty (D-013) | Start with WIDE=1 and PULL_THRESH=16, then execute JMP !OSRE | OSR count is 16 at ENABLE. The initial jump falls through. A successful PULL sets its count to zero and the same condition is then taken. |
| JMP X-- | Use X=1 and X=0 | Branch condition uses the old X. Decrement in both cases. The X=0 case falls through and wraps X to 0xFFFF. |
| WIDE PULL and PUSH (D-014) | Start with one TX byte or only one free RX slot, then provide a second | The blocked operation has no partial FIFO effect. Once eligible, transfer low and high bytes on consecutive engine ticks. Apply instruction delay after the second beat. |
| Shift count zero | Encode IN and OUT with count field zero | Interpret the field as 16 bits. Check both shift directions and the count update rather than treating the operation as a no-op. |
| EXEC (D-015) | Give a parent a delay and inject a jump, then repeat with a nested EXEC | Apply the parent delay before issuing the injected instruction. The injected jump determines PC. Nested EXEC faults ILLEGAL_OP with the parent's PC. |

[Lockstep reproduction](VERIFICATION.md#directed-isa-lockstep) · [Python model](../tools/pvm_iss.py)
