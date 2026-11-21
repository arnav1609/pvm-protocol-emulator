# Yosys reset-attribute comparison

Baseline `84174eea63f97dcdaafe61fe7653997017d00011`.
Candidate `00ec783b0bd7cdb23ad8a00df03c77ec840e2725`.
Tool Yosys 0.52, git `fee39a3284c90249e1d9684cf6944ffbbcbb8f90`.

From the repository root, prepare the archived source trees and run
identical synthesis and preprocessing in each.

```sh
scratch=$(mktemp -d)
mkdir "$scratch/before" "$scratch/after"
git archive 84174eea63f97dcdaafe61fe7653997017d00011 src | tar -x -C "$scratch/before"
git archive 00ec783b0bd7cdb23ad8a00df03c77ec840e2725 src | tar -x -C "$scratch/after"
cp evidence/pre_freeze/00ec783/yosys/*.ys "$scratch/"
cd "$scratch"
for side in before after; do
  (
    cd "$side"
    yosys -Q -l "../$side.synth.log" -p '
      read_verilog src/*.v
      synth -flatten -top tt_um_arnav1609_pvm -noabc
      stat
      write_json synth.json
    '
    yosys -Q -l "../$side.prep.log" -p '
      read_verilog src/*.v
      prep -flatten -top tt_um_arnav1609_pvm
      write_json native.json
    '
    yosys -Q -l "../$side.mapped.log" -p '
      read_verilog src/*.v
      prep -flatten -top tt_um_arnav1609_pvm
      memory_map
      opt
      async2sync
      write_rtlil converted.il
    '
    yosys -Q -l "../$side.reset-cone.log" -p '
      read_verilog src/*.v
      prep -flatten -top tt_um_arnav1609_pvm
      select -module tt_um_arnav1609_pvm
      select -assert-count 1 w:pvm.reset_release %ci1 t:$adff %i
      select w:pvm.reset_release %ci1 t:$adff %i
      submod -name reset_release_proof
      select -clear
      hierarchy -top reset_release_proof
      async2sync
      write_rtlil reset-cone.il
    '
  )
done
yosys -Q -l equiv-mapped.log -s equiv.ys
yosys -Q -l equiv-reset.log -s equiv-reset.ys
```

The native and synthesized JSON were each compared as complete parsed
objects after deleting only `ASYNC_REG` and the `src` location attribute
on `modules.tt_um_arnav1609_pvm.netnames["pvm.reset_release"]`. Both
comparisons matched. The native async reset cell has the same active-low
polarity, two-bit zero reset value and connectivity on both revisions.

[Per-cell counts and structure](structural.log) · [Full-top proof result](equiv-mapped.log) · [Full-top raw log](equiv-mapped.log.gz) · [Two-stage reset equivalence](equiv-reset.log)
