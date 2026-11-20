import binascii
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.pvm_asm import AsmError, assemble, main as asm_main
from tools.pvm_image import build_image, crc16_ccitt_false, main as image_main
from tools.pvm_wire import CONFIG_ADDRESSES, IMAGE_VER


EXAMPLES = Path(__file__).resolve().parents[1] / "examples"


class AssemblerTests(unittest.TestCase):
    def test_spec_worked_encodings(self):
        source = """out pins, 1 side 0 [7]
                    jmp x-- 2
                    set x, 7 side 0 [7]
                    pull block side 1 [7]
                    wait 0 pin 12
                    evt done"""
        self.assertEqual(list(assemble(source, side_count=1).values()),
                         [0x6701, 0x0042, 0xE727, 0x97A0, 0x200C, 0xC0C0])

    def test_jump_conditions_and_forward_labels(self):
        conditions = ("always", "!x", "x--", "!y", "y--", "x!=y", "pin", "!osre")
        source = "\n".join(f"jmp {cond}, END" for cond in conditions)
        words = assemble(source + "\nJMP end\nend: evt done")
        self.assertEqual(list(words.values()), [0x09, 0x29, 0x49, 0x69, 0x89, 0xA9, 0xC9, 0xE9, 0x09, 0xC0C0])

    def test_encodes_exec_shifts_fifo_flags_and_both_side_bits(self):
        # D-014 and D-015 semantics use the regular FIFO/EXEC encodings.
        source = """in fab, 16 side 2 [7]
                    out exec, 16 side 1 [7]
                    out exec, 0
                    mov exec, ~x
                    mov pc, ::osr
                    mov fab, status
                    pull ifempty noblock
                    push iffull block
                    evt clr 0
                    evt set 7
                    set fab, 0xA
                    wait 1 fab 3
                    wait 0 flag 5"""
        self.assertEqual(list(assemble(source, side_count=2).values()), [
            0x57C0, 0x6FE0, 0x60E0, 0xA069, 0xA096, 0xA0E4, 0x80C0,
            0x8060, 0xC040, 0xC007, 0xE0CA, 0x20A3, 0x2045,
        ])
        self.assertEqual(assemble("jmp 0 [31]")[0], 0x1F00)

    def test_sparse_addresses_and_raw_injected_words(self):
        source = ".org 0x5\nstart: jmp end // comment\n.org 0x1F\nend: .word 0xC001 # raw illegal word"
        self.assertEqual(assemble(source), {5: 31, 31: 0xC001})

    def test_reports_malformed_or_illegal_source_at_original_line(self):
        cases = (
            ("jmp missing", 0), ("jmp 32", 0), ("wait 1 pin 20", 0),
            ("wait 0 fab 4", 0), ("in pins, 17", 0), ("out exec, 8", 0),
            ("evt set 0", 0), ("set pc, 1", 0), ("push ifempty", 0),
            ("pull block noblock", 0), ("set pins, 1 side 1", 0),
            ("jmp 1 side 2", 1), ("jmp 1 [16]", 1), ("jmp 1 [8]", 2),
            (".word 0x10000", 0), (".org 32", 0), ("jmp 0 [x]", 0),
        )
        for source, side_count in cases:
            with self.subTest(source=source), self.assertRaisesRegex(AsmError, "line 2:"):
                assemble("# comment\n" + source, side_count=side_count)
        with self.assertRaisesRegex(AsmError, "line 2: duplicate label"):
            assemble("again: jmp again\nAgain: evt done")
        with self.assertRaisesRegex(AsmError, "line 33: program exceeds"):
            assemble("evt done\n" * 33)

    def test_assembler_cli_produces_addressed_readmemh_words(self):
        with TemporaryDirectory() as directory:
            source = Path(directory) / "test.pvm"
            hexfile = Path(directory) / "test.hex"
            source.write_text(".org 3\nset x, 2\n.org 10\nevt done\n", encoding="utf-8")
            asm_main([str(source), str(hexfile)])
            self.assertEqual(hexfile.read_text(encoding="utf-8"), "@03 E022\n@0A C0C0\n")


class ImageTests(unittest.TestCase):
    def test_crc_over_ordered_complete_writes_and_not_preload(self):
        self.assertEqual(crc16_ccitt_false(b"123456789"), 0x29B1)
        image = build_image({31: 0xC0C0, 1: 0xE027}, image_version=42, tx_preload=[0xFF])
        self.assertEqual(image["format"], "pvm-image-v1")
        self.assertEqual(image["writes"][:4], [[2, 0x27], [3, 0xE0], [62, 0xC0], [63, 0xC0]])
        self.assertEqual(tuple(address for address, _ in image["writes"][4:-1]), CONFIG_ADDRESSES)
        self.assertEqual(image["writes"][-1], [IMAGE_VER, 42])
        self.assertEqual(image["tx_preload"], [0xFF])
        self.assertEqual(image["crc16"], binascii.crc_hqx(bytes(value for _, value in image["writes"]), 0xFFFF))
        self.assertEqual(image["crc16"], build_image({1: 0xE027, 31: 0xC0C0}, image_version=42)["crc16"])
        config = dict(image["writes"][4:-1])
        self.assertEqual((config[0x010A], config[0x010B], config[0x010F]), (1, 31, 1))
        self.assertTrue(all(value == 0 for addr, value in config.items() if addr not in (0x010A, 0x010B, 0x010F)))

    def test_rejects_unmapped_and_invalid_configuration(self):
        cases = (
            ({0x0108: 4}, "reserved"), ({0x0F08: 1}, "writable configuration"),
            ({0x0303: 1}, "writable configuration"), ({0x0400: 9}, "conflicting"),
            ({0x0405: 0x11}, "conflicting"), ({0x040C: 0x17}, "invalid owner"),
            ({0x0103: 17}, "OUT_CNT"), ({0x0105: 6}, "SET_CNT"),
            ({0x0107: 20}, "SIDE_BASE"), ({0x0108: 3}, "SIDE_CNT"),
            ({0x010A: 1}, "WRAP_BOTTOM"), ({0x010F: 1}, "ENTRY_PC"),
            ({0x010D: 9}, "PULL_THRESH"), ({0x010C: 16, 0x010E: 17}, "PUSH_THRESH"),
            ({0x020C: 3}, "invalid output mode"), ({0x0222: 4}, "CNT_EN"),
            ({0x0224: 1}, "ARB_N"), ({0x0224: 0x11}, "ARB_SDA"),
            ({0x0224: 0x11, 0x0225: 12}, "open-drain"),
            ({0x0301: 0xE0}, "invalid guard"), ({0x0301: 0x80, 0x0302: 0x1C}, "invalid guard"),
        )
        for config, message in cases:
            with self.subTest(config=config), self.assertRaisesRegex(ValueError, message):
                build_image({0: 0xC0C0}, config=config)

    def test_rejects_invalid_image_word_version_or_preload(self):
        for words, kwargs in (({}, {}), ({32: 0}, {}), ({0: 65536}, {}),
                              ({0: 0}, {"image_version": 256}),
                              ({0: 0}, {"tx_preload": range(5)}),
                              ({0: 0}, {"tx_preload": [256]})):
            with self.subTest(words=words, kwargs=kwargs), self.assertRaises(ValueError):
                build_image(words, **kwargs)

    def test_examples_build_to_the_pin_level_bench_images(self):
        # Known-good word streams and nonzero settings from tb_rtl/tb_protocols.v.
        programs = (
            ("uart_tx", [0x35], [0xE001, 0x80A0, 0xE027, 0xE100, 0x6001, 0x0044, 0xE101, 0xC0C0], {
                0x0100: 217, 0x0102: 5, 0x0103: 1, 0x0104: 5, 0x0105: 1,
                0x010B: 7, 0x010C: 1, 0x0405: 0x29,
            }),
            ("spi_mode0", [0xA6, 0xC9], [0xE041, 0x80A0, 0xE027, 0x6001, 0x1043, 0x0081, 0xC0C0], {
                0x0100: 32, 0x0102: 7, 0x0103: 1, 0x0107: 6, 0x0108: 1,
                0x010B: 6, 0x0406: 0x0A, 0x0407: 0x09,
            }),
            ("i2c_write", [0xA0, 0x3C], [
                0xF003, 0xF083, 0x308D, 0xF002, 0xE041, 0x80A0, 0xE027, 0x6001, 0x308D,
                0x1047, 0xE001, 0x308D, 0x300C, 0x0085, 0xE000, 0x308D, 0xF003, 0xD0C0,
            ], {
                0x0100: 80, 0x0102: 12, 0x0103: 1, 0x0104: 12, 0x0105: 2,
                0x0107: 13, 0x0108: 1, 0x010B: 17, 0x040C: 0x11, 0x040D: 0x12,
            }),
        )
        for name, preload, words, config in programs:
            with self.subTest(program=name), TemporaryDirectory() as directory:
                output = Path(directory) / "image.json"
                args = [str(EXAMPLES / f"{name}.pvm"), str(output),
                        "--config", str(EXAMPLES / f"{name}.json")]
                for byte in preload:
                    args.extend(("--tx", hex(byte)))
                image_main(args)
                image = json.loads(output.read_text(encoding="utf-8"))
                expected = b"".join(word.to_bytes(2, "little") for word in words)
                self.assertEqual(image["writes"][:len(expected)], [list(pair) for pair in enumerate(expected)])
                self.assertEqual({addr: value for addr, value in image["writes"][len(expected):-1] if value}, config)
                self.assertEqual(image["tx_preload"], preload)


if __name__ == "__main__":
    unittest.main()
