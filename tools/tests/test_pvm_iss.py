"""Directed ISA checks with expected states from spec/04_ISA.md."""

import unittest

from tools.pvm_image import build_image
from tools.pvm_iss import Engine, Fault, Inputs, State


def engine(words, config=None, preload=()):
    return Engine.from_image(build_image(words, config=config, tx_preload=preload))


class InstructionModelTest(unittest.TestCase):
    def test_x_decrement_tests_old_value_then_wraps_at_16_bits(self):
        model = engine({0: 0x0040, 1: 0xC0C0})
        model.step()
        self.assertEqual((model.pc, model.x), (1, 0xFFFF))
        model.step()
        self.assertEqual((model.state, model.fault_code, model.fault_pc), (State.DONE, Fault.DONE, 1))

    def test_osr_initially_empty_then_jump_after_pull(self):
        model = engine({0: 0x00E0, 1: 0x80A0, 2: 0x00E4, 4: 0xC0C0}, preload=(0x35,))
        model.step()
        self.assertEqual(model.pc, 1)
        self.assertTrue(model.step().tx_pop)
        model.step()
        self.assertEqual(model.pc, 4)

    def test_wait_side_set_issues_before_stall_then_delay_starts_after_completion(self):
        model = engine({0: 0x328C, 1: 0xC0C0}, {0x107: 19, 0x108: 1})
        model.step()
        self.assertEqual((model.pc, model.out_val, model.delay), (0, 1 << 19, 0))
        model.step()
        self.assertEqual(model.pc, 0)
        model.step(Inputs(pins=1 << 12))
        self.assertEqual((model.pc, model.delay), (0, 2))
        model.step()
        self.assertEqual(model.pc, 0)
        model.step()
        self.assertEqual(model.pc, 1)

    def test_side_set_overrides_set_across_wrapped_pin_indices(self):
        config = {0x104: 19, 0x105: 2, 0x107: 19, 0x108: 2}
        model = engine({0: 0xF003, 1: 0xC0C0}, config)
        model.step()
        self.assertEqual(model.out_val, 1)  # side 2 writes P0=1 and P19=0

    def test_wide_pull_waits_for_both_bytes_and_completes_on_next_tick(self):
        model = engine({0: 0x80A0, 1: 0x6020, 2: 0xC0C0},
                       {0x100: 2, 0x10C: 17}, preload=(0x34,))
        for _ in range(4):
            self.assertFalse(model.step().tx_pop)
            self.assertEqual(list(model.tx), [0x34])
        model.tx.append(0x12)
        self.assertFalse(model.step().tx_pop)
        self.assertTrue(model.step().tx_pop)
        self.assertEqual(model.pc, 0)
        self.assertFalse(model.step().tx_pop)
        self.assertTrue(model.step().tx_pop)
        self.assertEqual((model.pc, model.osr), (1, 0x1234))
        model.step()
        model.step()
        self.assertEqual((model.x, model.osr_count), (0x1234, 16))

    def test_wide_autopush_checks_capacity_before_shift(self):
        # PULL 0x1234, then IN OSR, 16 with automatic WIDE push.
        model = engine({0: 0x80A0, 1: 0x40A0, 2: 0xC0C0}, {0x10C: 25}, (0x34, 0x12))
        model.rx.extend((1, 2, 3))
        model.step()
        model.step()
        self.assertIsNone(model.step().rx_byte)
        self.assertEqual((model.isr, model.isr_count, model.pc), (0, 0, 1))
        self.assertEqual(model.rx.popleft(), 1)
        self.assertEqual(model.step().rx_byte, 0x34)
        self.assertEqual(model.pc, 1)
        self.assertEqual(model.step().rx_byte, 0x12)
        self.assertEqual((model.pc, list(model.rx)), (2, [2, 3, 0x34, 0x12]))

    def test_exec_parent_and_injected_delay_apply_then_wrap(self):
        # PULL WAIT 1 PIN 12 [1], MOV EXEC, OSR [2] at WRAP_TOP.
        model = engine({0: 0x80A0, 1: 0xA266}, {0x10C: 17}, (0x8C, 0x21))
        for _ in range(2):
            model.step()
        self.assertEqual(model.pc, 1)
        model.step()
        self.assertEqual(model.delay, 2)
        model.step()
        model.step()
        self.assertFalse(model.stalled)
        model.step()
        self.assertTrue(model.stalled)
        model.step(Inputs(pins=1 << 12))
        self.assertEqual((model.pc, model.delay), (1, 1))
        model.step()
        self.assertEqual(model.pc, 0)

    def test_nested_exec_and_invalid_fetch_report_the_owning_pc(self):
        cases = (
            (engine({0: 0x80A0, 1: 0xA066}, {0x10C: 17}, (0x63, 0xA0)), Fault.ILLEGAL_OP),
            (engine({0: 0x0001, 2: 0xC0C0}), Fault.INVALID_WORD),
        )
        for model, fault in cases:
            with self.subTest(fault=fault):
                for _ in range(5):
                    model.step()
                self.assertEqual((model.state, model.fault_code, model.fault_pc), (State.FAULT, fault, 1))

    def test_timeout_and_same_tick_completion(self):
        words = {0: 0x208C, 1: 0xC0C0}
        for complete in (False, True):
            with self.subTest(complete=complete):
                model = engine(words, {0x110: 2, 0x112: 1})
                for _ in range(31):
                    model.step()
                model.step(Inputs(pins=int(complete) << 12))
                expected = (State.RUN, Fault.NONE, 1) if complete else (State.FAULT, Fault.TIMEOUT, 0)
                self.assertEqual((model.state, model.fault_code, model.pc), expected)


if __name__ == "__main__":
    unittest.main()
