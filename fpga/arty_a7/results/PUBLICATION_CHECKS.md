# FPGA publication check plan

Record these counts before testing the portable review checkout. Use the
immutable A1 handoff and the original reports as the evidence inputs.

| Check | Expected result |
| --- | --- |
| Handoff manifest | Match all archive entries listed in its manifest. |
| Frozen source | Match all 16 ordered RTL files byte for byte with the frozen ZIP and confirm the release commit has the same `src/` tree. |
| Effective FPGA build inputs | Compare the three wrapper or peripheral RTL files and one XDC with the A1 build-input hashes. |
| Saved board run | Recheck five readbacks against the archived contract and all six waveform CSVs with the relocated comparator. |
| Existing host/checker suite | Pass all 42 Python tests. Reuse the existing negative controls. |
| Repo paths | Load both relocated Tcl launchers with Tcl 8.6, confirm the expected scripts are resolved and exercise their path and argument guards. |
| Impl reports | Check each reported timing, resource, route and DRC value against the original run reports. |
| Publication boundary | Require only FPGA integration files and its handoff documentation. Confirm `src/` and `info.yaml` are identical to the review base. |

These checks rerun portable source and evidence validation. The board
results come from the saved physical run. Vivado routing and programming are
outside the relocation check.
