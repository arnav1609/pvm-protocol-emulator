# S08 Tiny Tapeout IHP CI

The integration source commit is `011cd45a36f0554f7cc1a2e2246504e21963b4cc`.
The project uses `ihp-sg13cmos5l`, 8x4 tiles, and a 50 MHz target.

| Check | State | Run |
| --- | --- | --- |
| RTL smoke test | Pass | [GitHub Actions test](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44682594879) |
| Datasheet build | Pass | [GitHub Actions docs](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44682594873) |
| GDS | In progress at last check | [GitHub Actions GDS](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44682594974) |
| Precheck | Awaiting GDS | [GitHub Actions GDS](https://github.com/arnav1609/pvm-protocol-emulator/actions/runs/44682594974) |

The IHP cell count, utilization, and setup WNS are pending. A local
Yosys 0.52 generic synthesis and structural check of the same RTL
completed with zero check errors. Its 9,160 generic cells are from
`synth -top tt_um_arnav1609_pvm -noabc`, without IHP mapping or routing.
