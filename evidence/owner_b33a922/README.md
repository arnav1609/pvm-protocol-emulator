# Owner verification on frozen RTL

Source `b33a9227ac187f791a3733b94ac4e32879b10414`. The technical
archive preserves the traceability tables, stated proof scope,
replay sources and raw campaign logs supplied in the owner handoff.
The source checksums were verified, and every included frozen spec
and bench matched the freeze tag byte for byte.
[Technical evidence archive](owner_verification_technical.zip) · [Fault job registry](check_registry.csv) · [Proof scope](property_results.csv)

- The clause inventory contains 306 entries with seven covered,
  273 partial, one gap and 25 inapplicable. The remaining explicit
  gap concerns monitor precision across pad and synchronizer phase.
- The SPI fault campaign reports three passing compound checks,
  144 seeded lifecycle commands, 24 validation scenarios and five
  mutants caught by their named assertions.
- The pin/FIFO and arbitration proofs are bounded to 16 steps.
  Config protection, RX acknowledgement and OSR initialization
  use two-step checks. Monitor non-intrusion has a structural cone
  audit and the existing directed RTL check.

To reproduce the attached campaign from the repository root, extract
the technical archive into a disposable directory. From that directory,
run either command with the checked-out repository's absolute path.

```sh
sha256sum -c SHA256SUMS.txt
bash Astra_owner_review/Verification_H4_H5/run_owner_checks.sh /path/to/pvm-protocol-emulator faults
bash Astra_owner_review/Verification_H4_H5/run_owner_checks.sh /path/to/pvm-protocol-emulator formal
```
