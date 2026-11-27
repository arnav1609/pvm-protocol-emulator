"""Replay the immutable handoff captures and exercise rejection cases."""

import csv
import io
from pathlib import Path
import sys
import tempfile
import unittest
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import compare_capture as capture  # noqa: E402


class CaptureTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.handoff = ZipFile(capture.DEFAULT_HANDOFF)
        self.addCleanup(self.handoff.close)

    def rows(self, protocol, index=0):
        name = capture.REFERENCES[protocol][index]
        return list(csv.reader(io.StringIO(self.handoff.read(name).decode())))

    def save(self, name, rows):
        path = self.folder / f"{name}.csv"
        with path.open("w", encoding="utf-8", newline="") as stream:
            csv.writer(stream).writerows(rows)
        return path

    def check(self, protocol, paths, *, sample_hz=capture.CORE_HZ, aliases=None, i2c_target="fixture"):
        return capture.compare(protocol, paths, capture.DEFAULT_HANDOFF, sample_hz,
                               aliases or {}, i2c_target)

    def test_all_pinned_references(self):
        for protocol, entries in capture.REFERENCES.items():
            with self.subTest(protocol=protocol):
                files = [self.save(f"{protocol}_{i}", self.rows(protocol, i)) for i in range(len(entries))]
                self.assertEqual(len(self.check(protocol, files)), len(entries))

    def ila_uart(self, column="pvm_arty_top/P5", packed=False):
        rows = [["Sample in Buffer", "Sample in Window", "TRIGGER", column],
                ["Radix", "UNSIGNED", "UNSIGNED", "HEX"]]
        for index, level, *_ in self.rows("uart")[1:]:
            value = f"{0xA0 | (int(level) << 2):X}" if packed else level
            rows.append([index, index, "0", value])
        return rows

    def test_ila_with_radix_and_hierarchical_probe(self):
        result = self.check("uart", [self.save("ila", self.ila_uart())])
        self.assertIn("0x35", result[0])

    def test_packed_ila_probe_alias(self):
        column = "bridge/wave[7:0]"
        artifact = self.save("packed", self.ila_uart(column, packed=True))
        self.assertTrue(self.check("uart", [artifact], aliases={"p5": f"{column}@2"}))

    def test_arty_ila_net_and_probe_names(self):
        uart = self.save("native_uart", self.ila_uart("pvm_arty_top/pvm_uo[0]"))
        self.assertTrue(self.check("uart", [uart]))

        rows = [["Sample in Buffer", "Sample in Window", "pvm_arty_top/pvm_uio_in[0]",
                 "analyzer/probe4[0:0]", "pvm_arty_top/pvm_uio_out[7:0]", "analyzer/probe10[7:0]"],
                ["Radix", "UNSIGNED", "BIN", "BIN", "HEX", "HEX"]]
        for index, _, _, _, sda, scl, uio_out, uio_oe in self.rows("i2c")[1:]:
            rows.append([index, index, sda, scl, f"{int(uio_out):02x}", f"{int(uio_oe):02x}"])
        result = self.check("i2c", [self.save("native_i2c", rows)])
        self.assertIn("PVM SDA release/open-drain checked", result[0])

    def test_routed_arty_ila_probe_names(self):
        # Probe names appear both as written in the LTX and as exported by Vivado.
        for probes in (("pvm_uo_1", "pvm_uo_2", "pvm_uo_3", "pvm_uio_in_1", "pvm_uio_in[1]"),
                       ("pvm_uo_1[0]", "pvm_uo_2[1]", "pvm_uo_3[2]", "pvm_uio_in_1[0]", "pvm_uio_in[1]"),
                       ("pvm_uo_1[0:0]", "pvm_uo_2[1:1]", "pvm_uo_3[2:2]", "pvm_uio_in_1[0:0]", "pvm_uio_in[1:1]")):
            header = ["Sample in Buffer", *probes, "pvm_uio_out[7:0]", "pvm_uio_oe[7:0]"]
            radix = ["Radix - UNSIGNED"] + ["HEX"] * (len(header) - 1)
            for protocol in ("uart", "spi", "i2c"):
                with self.subTest(protocol=protocol, probes=probes):
                    artifact = self.save(protocol, [header, radix, *self.rows(protocol)[1:]])
                    self.assertTrue(self.check(protocol, [artifact]))
        self.assertIsNone(capture.probe_column(["pvm_uo_2[0]"], "p6", {}))
        self.assertIsNone(capture.probe_column(["pvm_uo_2[0:0]"], "p6", {}))

    def test_quantized_external_uart(self):
        # Sample the immutable 50 MHz RTL levels on an independent 4 MS/s grid.
        sample_hz = 4_000_000
        levels = [int(row[1]) for row in self.rows("uart")[1:]]
        data = [["Time [s]", "Channel 0"]]
        for index in range(1 + (len(levels) - 1) * sample_hz // capture.CORE_HZ):
            level = levels[index * capture.CORE_HZ // sample_hz]
            data.append([f"{index / sample_hz:.12f}", level])
        artifact = self.save("external", data)
        self.assertTrue(self.check("uart", [artifact], sample_hz=sample_hz, aliases={"p5": "Channel 0"}))

    def test_external_i2c_has_no_fixture_stretch_requirement(self):
        source = self.rows("i2c")
        header, rows = source[0], source[1:]
        # Move the first ACK's rising edge earlier by removing a portion of low.
        # This is a parser fixture, not a measurement of an unstretched board.
        short = rows[:3281] + rows[3612:]
        for index, row in enumerate(short):
            row[0] = index
        artifact = self.save("external_i2c", [header] + short)
        self.assertTrue(self.check("i2c", [artifact], i2c_target="external"))
        with self.assertRaisesRegex(ValueError, "edge"):
            self.check("i2c", [artifact], i2c_target="fixture")

    def test_uart_pulse_extension_fails(self):
        rows = self.rows("uart")
        for cycle in range(1303, 1311):
            rows[1 + cycle][1] = "0"
        with self.assertRaisesRegex(ValueError, "p5 edge"):
            self.check("uart", [self.save("pulse_mutant", rows)])

    def test_uart_full_arm_preamble(self):
        header, *rows = self.rows("uart")
        # A board capture can start while P5 is idle before the arm pulse.
        padded = [["0", "1", *rows[0][2:]]]
        padded.extend([[int(row[0]) + 1, *row[1:]] for row in rows])
        self.assertTrue(self.check("uart", [self.save("uart_with_preamble", [header, *padded])]))
        for row in padded[219:225]:
            row[1] = "0"
        with self.assertRaisesRegex(ValueError, "Unexpected UART preamble"):
            self.check("uart", [self.save("uart_long_preamble", [header, *padded])])

    def test_spi_extra_clock_fails(self):
        rows = self.rows("spi")
        rows[1255][2] = "1"
        with self.assertRaisesRegex(ValueError, "16 SPI rising edges"):
            self.check("spi", [self.save("clock_mutant", rows)])

    def test_spi_mosi_parks_after_halt(self):
        header, *rows = self.rows("spi")
        park = 1249 + 33
        rows.extend([[cycle, *rows[-1][1:]] for cycle in range(len(rows), park + 20)])
        for row in rows[park:]:
            row[3] = "0"
        self.assertTrue(self.check("spi", [self.save("spi_with_park", [header, *rows])]))
        for row in rows[park - 4:park]:
            row[3] = "0"
        with self.assertRaisesRegex(ValueError, "Unexpected SPI MOSI park"):
            self.check("spi", [self.save("spi_early_park", [header, *rows])])

    def test_i2c_push_pull_mutant_fails(self):
        rows = self.rows("i2c")
        rows[402][6] = "1"
        with self.assertRaisesRegex(ValueError, "drove an open-drain line high"):
            self.check("i2c", [self.save("open_drain_mutant", rows)])

    def test_i2c_accepts_synchronized_target_release(self):
        header, *rows = self.rows("i2c")
        for ack_end in (3841, 6961):
            for row in rows[ack_end:ack_end + 3]:
                row[4] = "0"
        self.assertTrue(self.check("i2c", [self.save("i2c_sync_release", [header, *rows])]))
        for row in rows[3844:3846]:
            row[4] = "0"
        with self.assertRaisesRegex(ValueError, "sda edge"):
            self.check("i2c", [self.save("i2c_late_release", [header, *rows])])

    def test_i2c_cannot_release_target_before_ack_fall(self):
        header, *rows = self.rows("i2c")
        rows[3840][4] = "1"
        with self.assertRaisesRegex(ValueError, "sda edge"):
            self.check("i2c", [self.save("i2c_early_release", [header, *rows])])

    def test_i2c_ack_setup_glitch_fails(self):
        header, *rows = self.rows("i2c")
        for row in rows[3201:3204]:
            row[4] = "1"
        with self.assertRaisesRegex(ValueError, "sda: observed"):
            self.check("i2c", [self.save("i2c_ack_setup_glitch", [header, *rows])])

    def test_i2c_pvm_cannot_drive_sda_during_ack(self):
        header, *rows = self.rows("i2c")
        rows[3622][7] = "1"
        with self.assertRaisesRegex(ValueError, "PVM must release SDA"):
            self.check("i2c", [self.save("i2c_ack_contended", [header, *rows])])

    def test_board_fixture_accepts_small_pad_delays_without_changing_strict_fixture(self):
        header, *rows = self.rows("i2c")
        for column, delay in ((4, 5), (5, 4)):
            rising_cycles = [cycle for cycle in range(1, len(rows))
                             if rows[cycle - 1][column] == "0" and rows[cycle][column] == "1"]
            for cycle in rising_cycles:
                for row in rows[cycle:cycle + delay]:
                    row[column] = "0"
        artifact = self.save("board_i2c_delayed_rises", [header, *rows])
        measured = self.check("i2c", [artifact], i2c_target="board-fixture")
        self.assertIn("first ACK SCL low 415 core cycles", measured[0])
        self.assertIn("PVM SDA release/open-drain checked", measured[0])
        with self.assertRaisesRegex(ValueError, "scl edge"):
            self.check("i2c", [artifact])

    def test_board_fixture_requires_drive_direction_probes(self):
        artifact = self.save("board_i2c_missing_drive", [row[:-2] for row in self.rows("i2c")])
        with self.assertRaisesRegex(ValueError, "requires both uio_oe and uio_out"):
            self.check("i2c", [artifact], i2c_target="board-fixture")

    def test_board_fixture_rejects_bad_scl_phase(self):
        header, *rows = self.rows("i2c")
        for row in rows[721:735]:
            row[5] = "0"
        with self.assertRaisesRegex(ValueError, "SCL phase"):
            self.check("i2c", [self.save("board_i2c_bad_clock", [header, *rows])],
                       i2c_target="board-fixture")

    def test_board_fixture_rejects_bad_sda_setup(self):
        header, *rows = self.rows("i2c")
        for row in rows[641:655]:
            row[4] = "0"
        with self.assertRaisesRegex(ValueError, "SDA edge"):
            self.check("i2c", [self.save("board_i2c_bad_setup", [header, *rows])],
                       i2c_target="board-fixture")

    def test_board_fixture_rejects_missing_ack_stretch(self):
        header, *rows = self.rows("i2c")
        rows = rows[:3281] + rows[3612:]
        for cycle, row in enumerate(rows):
            row[0] = cycle
        with self.assertRaisesRegex(ValueError, "First ACK low"):
            self.check("i2c", [self.save("board_i2c_no_stretch", [header, *rows])],
                       i2c_target="board-fixture")

    def test_board_fixture_checks_both_ack_release_windows(self):
        for ack_fall in (3841, 6961):
            for release_delta in (-1, 13):
                with self.subTest(ack_fall=ack_fall, release_delta=release_delta):
                    header, *rows = self.rows("i2c")
                    if release_delta < 0:
                        rows[ack_fall + release_delta][4] = "1"
                    else:
                        for row in rows[ack_fall:ack_fall + release_delta]:
                            row[4] = "0"
                    with self.assertRaisesRegex(ValueError, "SDA ACK release"):
                        self.check("i2c", [self.save("board_i2c_bad_release", [header, *rows])],
                                   i2c_target="board-fixture")

    def test_board_fixture_rejects_extra_sda_pulse(self):
        header, *rows = self.rows("i2c")
        for row in rows[3201:3204]:
            row[4] = "1"
        with self.assertRaisesRegex(ValueError, "sda edge counts"):
            self.check("i2c", [self.save("board_i2c_extra_pulse", [header, *rows])],
                       i2c_target="board-fixture")

    def test_board_fixture_rejects_high_drive_and_master_driven_ack(self):
        cases = ((401, 6, "drove an open-drain line high"), (3622, 7, "PVM must release SDA"))
        for cycle, column, message in cases:
            with self.subTest(cycle=cycle):
                header, *rows = self.rows("i2c")
                rows[cycle][column] = "1"
                with self.assertRaisesRegex(ValueError, message):
                    self.check("i2c", [self.save("board_i2c_invalid_drive", [header, *rows])],
                               i2c_target="board-fixture")

    def test_dmx_short_mab_fails(self):
        first = self.rows("dmx512")
        second = self.save("dmx_reload", self.rows("dmx512", 1))
        # Move the falling edge of the start code 400 clocks earlier.
        first[4][0] = str(int(first[4][0]) - 400)
        with self.assertRaisesRegex(ValueError, "p5 edge"):
            self.check("dmx512", [self.save("short_mab_mutant", first), second])

    def test_dmx_dense_window_must_include_complete_last_slot(self):
        sparse = [(int(cycle), level) for cycle, level in self.rows("dmx512")[1:]]
        start = next(cycle for cycle, level in sparse if level == "0")
        final = start + 126_200
        rows = [["Sample in Buffer", "Sample in Window", "pvm_uo[0]"]]
        level = sparse[0][1]
        edges = dict(sparse)
        for cycle in range(final + 1):
            level = edges.get(cycle, level)
            rows.append([cycle, cycle, level])
        reload = self.save("dmx_reload", self.rows("dmx512", 1))
        self.assertTrue(self.check("dmx512", [self.save("dmx_dense", rows), reload]))
        with self.assertRaisesRegex(ValueError, "final DMX slot completes"):
            self.check("dmx512", [self.save("truncated_dmx", rows[:-8]), reload])

    def test_fragmented_ila_fails(self):
        trace = self.ila_uart()
        del trace[60]
        with self.assertRaisesRegex(ValueError, "Gap in ILA"):
            self.check("uart", [self.save("gap", trace)])

    def test_split_ila_windows_fail(self):
        trace = self.ila_uart()
        trace[100][1] = "0"
        with self.assertRaisesRegex(ValueError, "one ILA capture window"):
            self.check("uart", [self.save("split", trace)])

    def test_dmx_missing_or_duplicate_reload_fails(self):
        initial = self.save("dmx_initial", self.rows("dmx512"))
        with self.assertRaisesRegex(ValueError, "two separate complete captures"):
            self.check("dmx512", [initial])
        with self.assertRaisesRegex(ValueError, "distinct initial-load and reload"):
            self.check("dmx512", [initial, initial])


if __name__ == "__main__":
    unittest.main()
