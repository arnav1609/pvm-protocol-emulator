# Pre-freeze 32-word program-fit study

The freeze gate covers 1-Wire and SWD, approved in chat on 21 November
2026. The other three candidates are deferred according to D-019. The
full outsider draw pool is 1-Wire, SWD, WS2812, PS/2 RX, and DMX512 TX.

The threshold is 32 instruction words per tested transaction, with
timing margin measured on the RTL using target bus models. A program
that still exceeds 32 words after one optimization pass requires the
owner's 64-word decision before tagging. If the two fit programs are
unfinished on 26 November, keep 32 words for the freeze and record
the uncovered case. The independent simulator and review gate still
applies.

## Scope

- 1-Wire uses the DS18B20 at standard speed. Check reset and presence,
  both command bytes `0xCC` and `0xB4`, and the returned power-supply
  bit. Exercise early presence, late presence, and no target.
- SWD uses an initialized ADIv5 link, one-cycle turnaround, and
  `ORUNDETECT=0`. Check a DPIDR read with the 32-bit OK response and
  parity rejection. AP read requests exercise WAIT and FAULT. Check
  return to idle after all responses. Link initialization and writes
  are outside the tested scope.

Neither program requires a host transaction between ENABLE and the
end of the wire transaction. The SPI host loads a complete image and
reads the result after the modeled transaction.

[Analog Devices DS18B20 data sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ds18b20.pdf) · [Arm ADIv5 specification, B4](https://documentation-service.arm.com/static/622222b2e6f58973271ebc21?token=)

## Frozen checks

Frozen on 21 November 2026 before simulation. Each job has one
compound pin-transaction check. The positive job must pass all its
scenarios. A mutation job must fail through the named criterion.

| Cocotb job | Check | Count | Expected outcome |
| --- | --- | ---: | --- |
| `fit_one_wire` | `ONE_WIRE_PIN_TRANSACTION` | 1 | All three scenarios pass |
| `fit_one_wire_neg_short_zero` | `ONE_WIRE_PIN_TRANSACTION` | 1 | `WRITE_ZERO_LOW` catches an undersized write-zero pulse |
| `fit_swd` | `SWD_DPIDR_PIN_TRANSACTION` | 1 | Valid parity in both states, bad parity, WAIT and FAULT pass |
| `fit_swd_neg_accept_bad_parity` | `SWD_DPIDR_PIN_TRANSACTION` | 1 | `SWD_PARITY_FLAG` catches acceptance of a corrupted parity bit |

These are program mutations in separately assembled images. The
frozen 67-job RTL and mutation registry stays directly comparable.

```sh
(cd test && PYTHONPATH=.. make COCOTB_TEST_MODULES=test_fit_protocols)
```

## Results

Both transactions fit on the routed candidate RTL `1a258a1`. The two
positive jobs passed and both mutants were caught. The 32-word
instruction memory meets the D-019 fit gate.

| Candidate | Words | Fits | CLKDIV at 50 MHz | Measured pad timing |
| --- | ---: | --- | ---: | --- |
| 1-Wire power-supply read | 19 | Yes | 200 | Reset low 520 µs and high 524 µs before the first slot, 40 µs and 44 µs above their minima. Write-zero low 68 µs, write-one low 8 µs, minimum recovery 8 µs, read initiation low 4 µs. |
| SWD read transaction | 32 | Yes | 20 | Minimum SWCLK high and low phases 400 ns. The target data was stable for at least 300 ns at the modeled pins before the rising edge, leaving 240 ns after budgeting three core clocks for input and output registration. |

The 1-Wire program samples presence near 64 µs. The model exercised
both ends of the allowed presence-onset range, both returned bit
values, and an absent target. The shortened write-zero pulse measured
32 µs and failed the frozen check. The model uses a logical pull-up.

The SWD test observed two one-clock turnarounds and eight idle clocks.
OK cases transferred the data and parity and exercised both parity
values and both corruptions. WAIT and FAULT cases transferred only
the ACK. The parity mutant raised FLAG 2 for corrupt data and failed
the frozen check. The clock varies with the instruction path and
reaches 1.25 MHz in the shortest cells. The image uses all 32 words.

Use the normal image builder with `one_wire.json` and two TX preloads,
`0xCC` and `0xB4`, or with `swd.json` and `0xA5` for DPIDR. The
bus models run each transaction without a host round-trip in the
timing window.
[Fit programs](../tools/examples/fit/) · [Pin models](../test/test_fit_protocols.py) · [Simulation and mutation log](../evidence/opt/fit_study.log)

The outsider draws from the full pool after the tag. If the draw
lands on 1-Wire or SWD, disclose the pre-freeze study and implement the
final program after the draw.
