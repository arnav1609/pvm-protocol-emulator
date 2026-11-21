# PVM owner source review

Candidate `00ec783b0bd7cdb23ad8a00df03c77ec840e2725`. Kalash owns every checkbox and the final verdict.
[Candidate evidence](pre_freeze_validation_00ec783.md) · [Candidate diff](https://github.com/arnav1609/pvm-protocol-emulator/commit/00ec783b0bd7cdb23ad8a00df03c77ec840e2725)

## Priority checks

- [ ] Check that the arbitration guard releases both outputs four clocks from the pad observation when detection is qualified. [Detection](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L33) · [Output guard](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_pin_guard.v#L52) · [Timing check](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_fabric.v#L242)
- [ ] Check that outside RUN, the bidirectional pins release and dedicated outputs return to the configured idle values on the registered output update. [Pin guard](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_pin_guard.v#L24)
- [ ] Check that D-017 asserts core reset asynchronously, releases just after rising edge two, and supplies the core blocks. Confirm the two RTL stages use ordinary flops without ASYNC_REG. [Reset RTL](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_top.v#L15) · [Reset contract](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/spec/rev/PVM-IF-D017-RESET-RELEASE.md) · [Reset bench](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_reset_sync.v)
- [ ] Check the 17-bit MIN/MAX arithmetic, including equality, subtraction underflow, and the overflow overrides. [Verdicts](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L95) · [Boundary tests](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_mon.v#L155)
- [ ] Check that the shared IN/MOV mux keeps both operand maps and that the shared shifters keep direction, bit placement and the count-zero encoding for 16 bits. [Source mux](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_engine.v#L242) · [Shifters](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_engine.v#L104) · [Equivalence evidence](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/results/opt_area_timing.md#local-verification)

## PINFABRIC

- [ ] Check that the config bank and fabric agree on the truth table and selector order. [Packing](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_cfg.v#L226) · [LUT address](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L41)
- [ ] Check that each group selects the specified input and bidirectional pins. [Pin groups](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L39)
- [ ] Check that only the second layer reads the first layer's registered outputs. [Layer wiring](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L49)
- [ ] Check that REG samples the LUT, RISE pulses on a rising value, and MAJ3 votes on the prior three samples. [Mode logic](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L57)
- [ ] Check that the counter starts from RELOAD and toggles after RELOAD + 1 enabled ticks. [Counter](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L79)
- [ ] Check that a Manchester write on the bit boundary queues the next bit while the previously queued bit is consumed. An empty queue on the boundary raises underrun. [Holding register](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L96)
- [ ] Check that the sticky flags survive the end of RUN and clear on reset, HALT, the host clear command, or the matching engine clear. [Flag clear](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_fabric.v#L120) · [Host clear wiring](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_top.v#L174)

## SPECMON

- [ ] Check that the lowest-numbered matching rule wins. [Priority](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L72)
- [ ] Check that rule sources can only be rewritten in HALT, the previous-value flop samples the selected source each clock, and no rule fires on the first active cycle. [Write gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_cfg.v#L181) · [History](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L59) · [Start gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L112)
- [ ] Check that interval, verdict and total counters saturate, while the four-slot log pointer wraps. [Timers and counters](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L130)
- [ ] Check the five log bytes in order: flags/rule, interval low/high, then timestamp low/high. Confirm that the timestamp advances only when RUN and MON_EN are active, holds across DONE, HALT and reload, wraps at 16 bits, and clears on chip reset. [D-021](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/spec/06_MONITOR.md#1-timebase) · [Clock gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L45) · [Log packing](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_mon.v#L115) · [Timestamp bench](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_mon_timestamp_pause.v#L203)
- [ ] Check that the monitor only reports into the host read path. [Monitor wiring](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_top.v#L182) · [Configuration read mux](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_cfg.v#L289)

## Top level and protocol integration

- [ ] Check that each block-disable define ties the removed block's outputs to zero and preserves pad wiring. [Variant ties](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/src/pvm_top.v#L162)
- [ ] Check SPI image load, fault recovery and reset while running across the four variants. [System bench](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_top.v) · [System gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/reports/S14_gate.md)
- [ ] Check UART byte 0x35, SPI mode 0 bytes 0xA6 and 0xC9, and the I²C write to address 0x50. Check clock stretching and that the controller releases SDA for both ACKs. [Protocol checks](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/tb_rtl/tb_protocols.v#L171) · [Protocol gate](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/reports/S14b_protocols_gate.md)

## Independent model review

- [ ] Record Heet’s independent review of the 1-Wire read sample and pull-up model and the SWD launch edges, turnaround and parity cases. [Fit study and prior SWD finding](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/results/fit_study.md) · [Bus models](https://github.com/arnav1609/pvm-protocol-emulator/blob/00ec783b0bd7cdb23ad8a00df03c77ec840e2725/test/test_fit_protocols.py)

## Owner decision

Owner verdict and reviewed SHA ________________________________________

Date and findings _____________________________________________________
