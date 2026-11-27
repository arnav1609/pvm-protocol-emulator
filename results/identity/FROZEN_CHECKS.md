# A3 frozen author checks

This inventory was written before executing the test harness. All ten cases are required. A timeout, missing environment input, unexpected exit code or missing diagnostic fails the case.

| Case | Commit or input | Runtime | Expected exit and evidence |
| --- | --- | --- | --- |
| R01 | `752ebb97824cfd1161581497c22d3c171c4c6ca9` | Routed | 0, PASS, 83 matching paths |
| R02 | `e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c` | Routed | 0, PASS, 83 matching paths |
| R03 | `752ebb97824cfd1161581497c22d3c171c4c6ca9` | RTL | 0, PASS, 83 matching paths |
| R04 | `e1018ff505ae4e2b2d8c0ee1f4753083b8e97e0c` | RTL | 0, PASS, 83 matching paths |
| R05 | `0d2978a47e5e854d6881714b6bed72cc6ec72053` | Routed | 1, FAIL, 83 matching paths and 13 added matrix paths |
| R06 | Isolated scratch commit derived from `752ebb9` | Routed | 1, FAIL, `src/project.v` is the only changed path |
| R07 | `752ebb9` and installed Icarus 12 compiler and runtime | Routed | 1, FAIL, Icarus compiler and runtime rows fail while other tool rows match |
| R08 | `752ebb9` and installed Verilator 5.020 | Routed | 1, FAIL, Verilator reports 5.020 while other tool rows match |
| R09 | `752ebb9` and a reduced PATH without Verilator | Routed | 1, FAIL, Verilator row reports it is absent while other tool rows match |
| R10 | Deliberately unresolved ref | Routed | 2, error diagnostic names the ref and no report is printed |

R01–R06 require passing runtime rows for Python, Icarus compiler, Icarus runtime, cocotb and Verilator. R07–R09 require all 83 protected files to match. The mutation changes exactly one byte in the blob for `src/project.v` via the object database and index of a temporary clone. Neither checkout contains a modified source file. Each test accepts one observed exit status only and records the command, standard output and standard error.
