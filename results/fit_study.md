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
  `ORUNDETECT=0`. Check the DPIDR read request, OK/WAIT/FAULT ACK,
  the 32-bit OK response, parity rejection, and the return to idle.
  Link initialization and other transactions are outside the tested
  scope.

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

Simulation pending. The outsider draws from the full pool after the
tag. If the draw lands on 1-Wire or SWD, disclose the pre-freeze study
and implement the final program after the draw.
