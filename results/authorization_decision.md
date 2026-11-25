# Authorization decision brief

**Evidence checked 25 November 2026.** The competition baseline
remains the verified PVM design. Hold on-chip authorization for the
10 December decision unless both trust hardware and physical
qualification are available by then.

| Decision evidence | Status |
| --- | --- |
| Protected key storage | No confirmed macro or manufacturing provisioning flow for the SG13CMOS5L shuttle |
| Reset freshness | No confirmed qualified entropy source or durable, rollback-safe boot counter for this shuttle |
| Layout, timing views and licence | No approved exact cell, GDS/LEF, Liberty views or shuttle and open-source licence terms |
| Integrated implementation | Trusted-input top passed simulation and zero-delay mapped tests with fixture trust. The competition wrapper ties trust invalid. |
| Physical fit | Integrated SRAM route candidate mapped to 747,448 µm² including the SRAM macro, about 2.45× the frozen mapped area of 304,579 µm². A production trust provider and full 8×4 route remain open. |

An inquiry was sent to IHP on 23 November about SG13CMOS5L
protected key storage, reset freshness, physical and timing views,
provisioning, and open-source competition use. No reply was visible
in the connected sending inbox on 25 November. The inquiry supplied a
separate Reply-To mailbox. Treat an exact IHP response as new
evidence when it is available.
[Integrated candidate report](https://github.com/arnav1609/pvm-protocol-emulator/blob/68bd2de71f1301e948051f490d632b38c4dac66f/results/authorization_candidate.md) · [Public SG13CMOS5L libraries](https://github.com/IHP-GmbH/IHP-Open-PDK/tree/89d42ee6d2fd9b50b86a1aada6fee6673c3e6008/ihp-sg13cmos5l/libs.ref) · [IHP Open130-G2 security IP announcement](https://www.ihp-microelectronics.com/news/detail/ihp-ememory-and-its-subsidiary-company-pufsecurity-break-ground-on-open-access-to-hardware-puf-based-security-ip-in-europe)

If those conditions are still open at the cutoff, describe on-chip
authorization as future work. A separate board-level prototype can
enforce authorization only if its controller has exclusive access to
the PVM SPI and reset lines. This keeps the trust boundary on the
board. Kalash owns the go/no-go and the competition submission uses
the verified baseline either way.
