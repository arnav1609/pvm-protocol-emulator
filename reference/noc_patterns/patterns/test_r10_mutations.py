"""Mutation adapter negative tests, before the I-27 registry is generated."""
from pathlib import Path
import unittest
from dual_lane import mutation
from dual_lane_verify import InvalidEvidence
ROOT=Path(__file__).resolve().parents[1]
class Controls(unittest.TestCase):
    def test_registered_mutations(self):
        for rel,kind in [('rtl/riscv/meas_imem_hasher.sv','rvh_skip_word'),('rtl/riscv/addr_decode.sv','rvd_fetch_guard_off')]:
            text=(ROOT/rel).read_text();changed=mutation(text,kind)
            self.assertNotEqual(text,changed)
            with self.assertRaises(InvalidEvidence):mutation(changed,kind)
            with self.assertRaises(InvalidEvidence):mutation('module unrelated;endmodule',kind)
    def test_unknown_mutation(self):
        with self.assertRaises(InvalidEvidence):mutation('module m;endmodule','rvh_unknown')
if __name__=='__main__':unittest.main()
