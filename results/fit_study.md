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

[Analog Devices DS18B20 data sheet, Read Time Slots and Figure 17](https://www.analog.com/media/en/technical-documentation/data-sheets/ds18b20.pdf#page=16) · [Arm ADIv5 IHI 0031G, §§B4.2.2 and B4.3.1](https://documentation-service.arm.com/static/622222b2e6f58973271ebc21?token=)

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

These four jobs are cocotb-simulated outside the `pvm_run.py` registry.
They use program mutations in separately assembled images and have
their own frozen check counts.

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
| SWD read transaction | 32 | Yes | 20 | Minimum SWCLK high and low phases 400 ns. Target data was stable for at least 690 ns before the modeled rising pad edge, leaving 630 ns after budgeting three core clocks for input and output registration. |

For both returned 1-Wire bit values, the engine captured the read bit
**11.98 µs** after the falling edge that started the slot, leaving
**3.02 µs** against the 15 µs deadline. The slot ended at the RX FIFO
push **75.98 µs** after that edge, or **15.98 µs** beyond the 60 µs
minimum. The image entered DONE at **80.00 µs**. These timestamps
come from the pad drive, ISR, and FIFO transitions in simulation.
[DS18B20 read slot timing](https://www.analog.com/media/en/technical-documentation/data-sheets/ds18b20.pdf#page=16)

The 1-Wire program samples presence near 64 µs. The model exercised
both ends of the allowed presence-onset range, both returned bit
values, and an absent target. The shortened write-zero pulse measured
32 µs and failed the frozen check. The model uses an ideal digital
pull-up and omits physical rise time.

The SWD test observed two one-clock turnarounds and eight idle clocks.
OK cases transferred the data and parity and exercised both parity
values and both corruptions. WAIT and FAULT cases transferred only
the ACK. The parity mutant raised FLAG 2 for corrupt data and failed
the frozen check. The clock varies with the instruction path and
reaches 1.25 MHz in the shortest cells. The image uses all 32 words.

ADIv5 §B4.3.1 specifies that the target samples SWDIO and changes or
releases its drive at SWCLK rising edges. §B4.2.2 and Figure B4-2
show the read and its turnarounds. The original model changed target
data after falling edges, so it masked a parity bug. With target
data advancing after rising edges, the original program rejected a
valid even-parity response. The corrected 32-word program tests the
data bit for parity before the rising edge that advances the target.
[Arm ADIv5 IHI 0031G](https://documentation-service.arm.com/static/622222b2e6f58973271ebc21?token=)

P5 is the dedicated SWCLK output. Its config byte `0x0A` sets
`IDLE=0`. The pin guard drives that idle value outside RUN. The
reload simulation watched P5 continuously from DONE through HALT,
loading a different image with the same P5 setting, and READY.
It stayed low throughout. Any later SWD images should keep that idle
setting when swapping between setup, read, and write programs.
[Pin guard](../src/pvm_pin_guard.v) · [SWD configuration](../tools/examples/fit/swd.json)

This study uses the D-017/D-018 routed RTL at `1a258a1`.
Precheck passed on workflow `44862976826`, job `136742889835`.
[Precheck job](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44862976826/job/136742889835)

Use the normal image builder with `one_wire.json` and two TX preloads,
`0xCC` and `0xB4`, or with `swd.json` and `0xA5` for DPIDR. The
bus models run each transaction without a host round-trip in the
timing window.
[Fit programs](../tools/examples/fit/) · [Pin models](../test/test_fit_protocols.py) · [Corrected simulation and mutation log](../evidence/opt/fit_timing_followup.log)

## Independent model review

Heet reproduced four fit-study jobs on frozen RTL, including detection
of both program mutations, and separately reviewed the protocol models.
He reported a 1-Wire sensitivity check in which the model delayed the
high level to 13 µs and the receiver read zero at its 11.98 µs sample.
He also reproduced the original SWD program’s parity rejection under
the corrected model. These are digital results. The modeled target and
the measured timing limits above define their scope.

The one-time post-freeze draw used the full pool and selected DMX512 TX.
[Draw record](held_out_draw.md)
