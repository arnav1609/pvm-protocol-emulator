# Arty A7 publication handover

The repository overlay is based on the release review commit
`0d2978a47e5e854d6881714b6bed72cc6ec72053`. The physical run used the original
`JANE_STREET.xpr`, with the A1 overlay through
`8478b27d58f6483280f1889f42c1de8274ea3ad3` and the archived host and capture
fixes. The [A1 input archive and report hashes](implementation.sha256)
identify the measured implementation. The original A1 checkout and
handoff were retained.

| Check | Count | Outcome |
| --- | ---: | --- |
| Original handoff manifest | 75 | PASS_FRESH |
| Ordered frozen RTL and FPGA build inputs | 16 + 4 | PASS_FRESH. The frozen Git blobs and FPGA overlay hashes matched. |
| Saved board evidence checksums | 10 | PASS_FRESH |
| USB status and image readbacks | 5 | PASS_FRESH against the supplied reference contract. |
| ILA comparisons | 6 | PASS_FRESH on the archived physical captures. The relocated PowerShell checker passed the sequence and waveforms. |
| Existing host and CSV-reader unit tests | 42 | PASS_FRESH, including the existing parser and host negative controls. |
| Tcl source layout | 3 scripts | PASS_FRESH for Tcl parsing and offline project and COM guards. The in-place updater registered 19 sources and one XDC in a mock project. |
| Original Vivado implementation reports | 5 | PASS_FRESH against the reported setup, hold, route, resources, DRC and power evidence status. |

Use the [board guide](../README.md) for the archived input filenames,
build commands, capture and comparison. The existing Python suite runs
from the repository root with
`python -B -m unittest discover -s fpga/arty_a7/sim -p "test_*.py"`.
After a capture, the Windows sequence and waveform replay runs with
`.\fpga\arty_a7\scripts\Run-PvmBoard.ps1 -Check <capture-dir>`.

The board run evidence is in the [capture manifest](SHA256SUMS.txt),
[host log](host.log), [waveform comparison log](comparisons.log) and
[readback record](readback.jsonl). This publication check replayed the
saved captures without running a new Vivado implementation or board test.
The wrapper mutation results belong to the original A1 handoff. A numerical
power result and external-device checks remain open.
