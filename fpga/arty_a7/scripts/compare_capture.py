"""Compare a PVM board capture with the frozen Arnav handoff.

Use one continuous ILA window, a timestamped analyzer CSV, or an RTL CSV
from the handoff. Timestamps in each file are relative to its own trigger.
"""

import argparse
from bisect import bisect_right
import csv
from dataclasses import dataclass
from functools import cached_property
import io
import math
from pathlib import Path
import re
import sys
from zipfile import BadZipFile, ZipFile


CORE_HZ = 50_000_000
BOARD_TOLERANCE_PPM = 100
# Local timing budget for the physical pad threshold and sampling, in 20 ns clocks.
I2C_BOARD_PAD_CYCLES = 8
DEFAULT_HANDOFF = Path(__file__).resolve().parents[1] / "inputs" / "PVM_Arty_A7_Handoff_b33a922.zip"
REFERENCES = {
    "uart": ("evidence/uart_tx/pins.csv",),
    "spi": ("evidence/spi_mode0/pins.csv",),
    "i2c": ("evidence/i2c_write/pins.csv",),
    "dmx512": ("evidence/dmx512_tx/run_1_p5.csv", "evidence/dmx512_tx/run_2_p5.csv"),
}
SIGNALS = {"reset": ("pvm_reset_n",), "uart": ("p5",), "spi": ("p6", "p7"),
           "i2c": ("sda", "scl"), "dmx512": ("p5",)}
OPTIONAL_I2C = ("uio_oe", "uio_out")
MINIMUM_SAMPLE_HZ = {"reset": CORE_HZ, "uart": 4_000_000, "spi": 24_000_000,
                     "i2c": 4_000_000, "dmx512": 4_000_000}
# The Arty overlay wires these named nets to the corresponding ILA probe ports.
BOARD_PROBES = {
    "pvm_reset_n": ("probe9",),
    "p5": ("pvm_uo[0]", "protocol_out[0]", "probe0"),
    "p6": ("pvm_uo[1]", "protocol_out[1]", "probe1"),
    "p7": ("pvm_uo[2]", "protocol_out[2]", "probe2"),
    "sda": ("pvm_uio_in[0]", "protocol_io[0]", "probe3"),
    "scl": ("pvm_uio_in[1]", "protocol_io[1]", "probe4"),
    "uio_oe": ("pvm_uio_oe", "probe10"),
    "uio_out": ("pvm_uio_out", "probe11"),
}
# Vivado 2024.1 can rename separate bits during implementation, as in debug_nets.ltx.
ROUTED_PROBES = {
    "p5": ("pvm_uo_1", "pvm_uo_1[0]"),
    "p6": ("pvm_uo_2", "pvm_uo_2[1]"),
    "p7": ("pvm_uo_3", "pvm_uo_3[2]"),
    "sda": ("pvm_uio_in_1", "pvm_uio_in_1[0]"),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


@dataclass(frozen=True)
class Trace:
    edges: dict
    end: float
    sample_cycles: float
    sparse_core: bool

    @cached_property
    def times(self):
        return {signal: tuple(t for t, _ in events) for signal, events in self.edges.items()}

    def value(self, signal, time):
        return self.edges[signal][max(0, bisect_right(self.times[signal], time) - 1)][1]


def column_key(name):
    key = name.strip().split("/")[-1].casefold()
    # ILA CSV export can spell a one-bit slice as [n:n] even when the LTX uses [n].
    return re.sub(r"\[(\d+):\1\]$", r"[\1]", key)


def probe_column(headers, signal, aliases):
    if signal not in aliases:
        names = (signal,) + BOARD_PROBES[signal]
        vector_suffix = "[7:0]" if signal in OPTIONAL_I2C else "[0]"
        accepted = set(names)
        accepted.update(probe + vector_suffix for probe in names if not probe.endswith("]"))
        accepted.update(ROUTED_PROBES.get(signal, ()))
        matches = [index for index, name in enumerate(headers) if column_key(name) in accepted]
        require(len(matches) <= 1, f"Ambiguous {signal} probe. Use --column.")
        return (matches[0], None) if matches else None

    header, marker, bit = aliases[signal].rpartition("@")
    if not marker:
        header = aliases[signal]
        bit_index = None
    else:
        bit_index = int(bit)
        require(bit_index >= 0, f"Negative bit index for {signal}")
    matches = [index for index, name in enumerate(headers) if name == header]
    require(len(matches) == 1, f"No unique CSV column named {header!r} for {signal}")
    return matches[0], bit_index


def time_column(headers, sample_hz):
    normalized = {name.casefold(): index for index, name in enumerate(headers)}
    if "core_cycle" in normalized:
        return normalized["core_cycle"], 1.0, "core"
    if "sample in buffer" in normalized:
        return normalized["sample in buffer"], CORE_HZ / sample_hz, "ila"
    time_units = {"s": 1, "ms": 1e-3, "us": 1e-6, "ns": 1e-9}
    for name, index in normalized.items():
        match = re.fullmatch(r"time\s*(?:[\[(]\s*(ms|us|ns|s)\s*[])]\s*)?", name)
        if match:
            return index, CORE_HZ * time_units[match.group(1) or "s"], "timestamp"
    raise ValueError("CSV needs core_cycle, Sample in Buffer, or a Time column")


def signal_value(raw, radix, bit_index):
    if raw.lower().startswith(("0b", "0x")):
        number = int(raw, 0)
    else:
        base = {"HEX": 16, "HEXADECIMAL": 16, "BINARY": 2, "BIN": 2, "OCTAL": 8}.get(radix, 10)
        number = int(raw, base)
    require(number >= 0, f"Expected an unsigned probe value, got {raw!r}")
    return number if bit_index is None else (number >> bit_index) & 1


def read_trace(stream, protocol, sample_hz, aliases):
    reader = csv.reader(stream)
    headers = [name.strip().lstrip("\ufeff") for name in next(reader, [])]
    require(headers, "Empty capture")
    t_index, scale, kind = time_column(headers, sample_hz)
    if kind != "core":
        require(sample_hz >= MINIMUM_SAMPLE_HZ[protocol],
                f"{protocol} needs at least {MINIMUM_SAMPLE_HZ[protocol]} samples/s")
    window_index = next((i for i, name in enumerate(headers)
                         if name.casefold() == "sample in window"), None)
    columns = {}
    expected = SIGNALS[protocol] + (OPTIONAL_I2C if protocol == "i2c" else ())
    require(set(aliases).issubset(expected), "A --column signal is not used by this protocol")
    for signal in expected:
        column = probe_column(headers, signal, aliases)
        if column is not None:
            columns[signal] = column
        else:
            require(signal in OPTIONAL_I2C, f"Missing {signal} probe. Use --column.")
    require(("uio_oe" in columns) == ("uio_out" in columns),
            "To check open-drain direction, supply both uio_oe and uio_out")

    edges = {signal: [] for signal in columns}
    radices = [""] * len(headers)
    origin = previous = None
    window_origin = None
    sparse_core = False
    end = 0
    for number, fields in enumerate(reader, 2):
        if not any(field.strip() for field in fields):
            continue
        require(len(fields) == len(headers), f"CSV row {number} has wrong column count")
        if (kind == "ila" and origin is None
                and fields[t_index].strip().casefold() in {"radix", "radix - unsigned"}):
            radices = [field.strip().upper() for field in fields]
            continue
        try:
            position = float(fields[t_index]) if kind == "timestamp" else int(fields[t_index])
            require(math.isfinite(position), "Non-finite time")
            if origin is None:
                origin = position
                if kind == "ila" and window_index is not None:
                    window_origin = int(fields[window_index])
            else:
                require(position > previous, "Samples must advance in strictly increasing order")
                if kind == "ila":
                    require(position == previous + 1, "Gap in ILA sampling")
                if kind == "core" and position != previous + 1:
                    require(protocol == "dmx512", "Gap in per-cycle RTL trace")
                    sparse_core = True
            if kind == "ila" and window_index is not None:
                require(int(fields[window_index]) - window_origin == position - origin,
                        "Use one ILA capture window")
            end = (position - origin) * scale
            previous = position
            for signal, (index, bit_index) in columns.items():
                value = signal_value(fields[index].strip(), radices[index], bit_index)
                upper = 255 if signal in OPTIONAL_I2C else 1
                require(value <= upper, f"{signal} is outside its capture width. For a packed probe use @bit.")
                events = edges[signal]
                if not events or events[-1][1] != value:
                    events.append((end, value))
        except ValueError as error:
            raise ValueError(f"CSV row {number}: {error}") from error
    require(previous is not None and previous > origin, "Capture needs at least two distinct samples")
    return Trace(edges, end, 1.0 if kind == "core" else CORE_HZ / sample_hz, sparse_core)


def near(observed, expected, sample_cycles):
    return abs(observed - expected) <= sample_cycles + abs(expected) * BOARD_TOLERANCE_PPM / 1_000_000


def compare_edges(measured, reference, signal, start, golden_start, sample_cycles, windows=None):
    require(len(measured) == len(reference),
            f"{signal}: observed {len(measured)} transitions, expected {len(reference)}")
    windows = windows or {}
    for index, ((time, value), (wanted_time, wanted_value)) in enumerate(zip(measured, reference), 1):
        if wanted_time in windows:
            earliest, latest = windows[wanted_time]
            correct_time = earliest <= time <= latest + sample_cycles
            expected_time = f"{earliest - start:g}..{latest - start:g}"
        else:
            correct_time = near(time - start, wanted_time - golden_start, sample_cycles)
            expected_time = f"{wanted_time - golden_start:g}"
        require(value == wanted_value and correct_time,
                f"{signal} edge {index}: got ({time - start:g}, {value}), expected ({expected_time},"
                f" {wanted_value}) relative core cycles")


def first_fall(trace, signal):
    for time, level in trace.edges[signal][1:]:
        if not level:
            return time
    raise ValueError(f"Missing falling start edge on {signal}")


def check_uart(trace, oracle):
    bit_cycles = 434
    require(trace.edges["p5"][-1][1] == 1, "UART must end idle high")
    golden_start = first_fall(oracle, "p5")
    reference = [(t, level) for t, level in oracle.edges["p5"][1:] if t >= golden_start]
    measured = trace.edges["p5"][1:]
    # PVM briefly parks P5 low when transitioning from an idle image to RUN.
    # The frozen capture starts at that low level. A board window can include its falling edge.
    if len(measured) == len(reference) + 2:
        (park, first_level), (idle, second_level), (frame, third_level) = measured[:3]
        require((first_level, second_level, third_level) == (0, 1, 0)
                and near(idle - park, 218, trace.sample_cycles)
                and near(frame - idle, 651, trace.sample_cycles),
                "Unexpected UART preamble before START")
        measured = measured[2:]
    elif trace.edges["p5"][0][1] == 0 and measured and measured[0][1] == 1:
        measured = measured[1:]
    require(measured and measured[0][1] == 0, "Missing UART START")
    start = measured[0][0]
    require(trace.end >= start + 9.5 * bit_cycles, "Capture ends before the UART stop-bit sample")
    compare_edges(measured, reference, "p5", start, golden_start, trace.sample_cycles)
    center = [trace.value("p5", start + (cell + 0.5) * bit_cycles) for cell in range(10)]
    data = sum(bit << i for i, bit in enumerate(center[1:9]))
    require((center[0], data, center[-1]) == (0, 0x35, 1), "Expected 8N1 LSB-first 0x35")
    return "UART 8N1 0x35 with 434 core clocks per bit"


def check_spi(trace, oracle):
    require(trace.edges["p6"][0][1] == 0, "SPI mode 0 clock must start idle low")
    rises = [t for t, level in trace.edges["p6"][1:] if level]
    require(len(rises) == 16, f"Expected 16 SPI rising edges, found {len(rises)}")
    golden_start = oracle.edges["p6"][1][0]
    clock = trace.edges["p6"][1:]
    compare_edges(clock, oracle.edges["p6"][1:], "p6", rises[0], golden_start, trace.sample_cycles)
    data_edges = trace.edges["p7"][1:]
    golden_data = oracle.edges["p7"][1:]
    # The frozen transaction capture ends before normal HALT parks MOSI low.
    if len(data_edges) == len(golden_data) + 1:
        park_time, park_level = data_edges[-1]
        require(park_level == 0 and near(park_time - clock[-1][0], 33, trace.sample_cycles),
                "Unexpected SPI MOSI park after the final falling clock")
        data_edges = data_edges[:-1]
    compare_edges(data_edges, golden_data, "p7", rises[0], golden_start, trace.sample_cycles)
    require(trace.edges["p6"][-1][1] == 0, "SPI clock did not return low")
    data = [trace.value("p7", t) for t in rises]
    payload = [sum(bit << (7 - i) for i, bit in enumerate(data[j:j + 8])) for j in (0, 8)]
    require(payload == [0xA6, 0xC9], "SPI payload differs from A6 C9")
    return "SPI mode 0, 16 rising edges, MSB-first A6 C9"


def i2c_events(trace):
    # START and STOP are transitions on SDA during a stable SCL high.
    # One sample of separation avoids counting coincident data/clock transitions.
    tolerance = trace.sample_cycles
    stable = [(t, v) for t, v in trace.edges["sda"][1:]
              if trace.value("scl", t - tolerance) and trace.value("scl", t + tolerance)]
    require(len(stable) == 2 and [v for _, v in stable] == [0, 1],
            "Expected exactly one START and one STOP")
    start, stop = (t for t, _ in stable)
    clocks = trace.edges["scl"][1:]
    require(len(clocks) == 38 and clocks[-1][1] == 1
            and all(start < t < stop for t, _ in clocks),
            "Expected 18 I²C bit clocks followed by one STOP clock release")
    rises = [t for t, v in clocks if v]
    falls = [t for t, v in clocks if not v]
    centers = [(rise + fall) / 2 for rise, fall in zip(rises[:18], falls[1:])]
    signs = [trace.value("sda", at) for at in centers]
    payload = [sum(bit << (7 - i) for i, bit in enumerate(signs[j:j + 8])) for j in (0, 9)]
    require(payload == [0xA0, 0x3C] and signs[8] == signs[17] == 0,
            "I²C transaction must send A0/ACK/3C/ACK")
    checks_oe = all(signal in trace.edges for signal in OPTIONAL_I2C)
    if checks_oe:
        observed = sorted(set(trace.times["uio_oe"]) | set(trace.times["uio_out"]))
        require(all(not (trace.value("uio_oe", t) & trace.value("uio_out", t) & 3) for t in observed),
                "PVM drove an open-drain line high")
        ack_samples = [t for slot in (8, 17) for t in [rises[slot], *trace.times["uio_oe"]]
                       if rises[slot] <= t < falls[slot + 1]]
        require(all(not trace.value("uio_oe", t) & 1 for t in ack_samples),
                "PVM must release SDA for both ACK bits")
    return start, rises[8] - falls[8], checks_oe, (falls[9], falls[18])


def check_board_i2c_edges(trace, oracle, observed, reference):
    start, ack_low, _, ack_falls = observed
    golden_start, golden_ack_low, _, golden_ack_falls = reference
    allowance = I2C_BOARD_PAD_CYCLES + trace.sample_cycles
    require(abs(ack_low - golden_ack_low) <= allowance,
            f"First ACK low was {ack_low:g}, expected {golden_ack_low:g} core cycles")

    for signal in ("scl", "sda"):
        require([level for _, level in trace.edges[signal]] == [level for _, level in oracle.edges[signal]],
                f"I²C {signal} edge counts or polarities differ from reference")

    scl = trace.times["scl"][1:]
    golden_scl = oracle.times["scl"][1:]
    previous, golden_previous = start, golden_start
    for index, (edge, golden_edge) in enumerate(zip(scl, golden_scl), 1):
        cycles = edge - previous
        golden_cycles = golden_edge - golden_previous
        require(abs(cycles - golden_cycles) <= allowance,
                f"I²C SCL phase {index}: got {cycles:g}, expected {golden_cycles:g} core cycles")
        previous, golden_previous = edge, golden_edge

    releases = dict(zip(golden_ack_falls, ack_falls))
    for index, (edge, golden_edge) in enumerate(zip(trace.times["sda"][1:], oracle.times["sda"][1:]), 1):
        if golden_edge in releases:
            relative = edge - releases[golden_edge]
            require(0 <= relative <= 3 + allowance,
                    f"I²C SDA ACK release at edge {index}: got {relative:g} core cycles after SCL fell")
        else:
            # Anchor every data transition to the matched local SCL edge to
            # budget pad delays per phase without allowing unbounded pulse error.
            anchor = min(range(len(golden_scl)), key=lambda item: abs(golden_scl[item] - golden_edge))
            offset = edge - scl[anchor]
            golden_offset = golden_edge - golden_scl[anchor]
            require(abs(offset - golden_offset) <= allowance,
                    f"I²C SDA edge {index}: got {offset:g}, expected {golden_offset:g} core cycles relative to SCL")


def check_i2c(trace, oracle, target):
    require(all(trace.edges[signal][0][1] == trace.edges[signal][-1][1] == 1
                for signal in SIGNALS["i2c"]), "I²C must start and end idle high")
    observed = i2c_events(trace)
    start, ack_low, checks_oe, ack_falls = observed
    if target == "fixture":
        golden_start, golden_ack_low, _, golden_ack_falls = i2c_events(oracle)
        compare_edges(trace.edges["scl"][1:], oracle.edges["scl"][1:], "scl", start,
                      golden_start, trace.sample_cycles)
        # Only the two target SDA releases may follow the ACK-ending SCL fall
        # by the three clocks of the FPGA fixture's synchronized edge detector.
        releases = {golden: (actual, actual + 3) for golden, actual in zip(golden_ack_falls, ack_falls)}
        compare_edges(trace.edges["sda"][1:], oracle.edges["sda"][1:], "sda", start,
                      golden_start, trace.sample_cycles, windows=releases)
        require(near(ack_low, golden_ack_low, trace.sample_cycles),
                f"First ACK low was {ack_low:g}, expected {golden_ack_low:g} core cycles")
    elif target == "board-fixture":
        require(checks_oe, "Board fixture requires both uio_oe and uio_out probes")
        check_board_i2c_edges(trace, oracle, observed, i2c_events(oracle))
    directions = "PVM SDA release/open-drain checked" if checks_oe else "ACK decoded at pins"
    return f"I²C START A0 ACK 3C ACK STOP, first ACK SCL low {ack_low:g} core cycles, {directions}"


def check_dmx(trace, oracle):
    require(trace.edges["p5"][0][1] == trace.edges["p5"][-1][1] == 1, "DMX must start and end idle high")
    start = first_fall(trace, "p5")
    golden_start = first_fall(oracle, "p5")
    # Match every transition against the accepted two-packet RTL waveform.
    # This includes the two BREAKs, two MABs, interpacket period, slots and data.
    compare_edges(trace.edges["p5"][1:], oracle.edges["p5"][1:], "p5", start, golden_start,
                  trace.sample_cycles)
    if not trace.sparse_core:
        # 64,000 clocks between BREAKs plus the last BREAK/MAB and 25 slots.
        full_run_cycles = 64_000 + 6_400 + 800 + 25 * 11 * 200
        require(trace.end >= start + full_run_cycles - trace.sample_cycles,
                "Capture ends before the final DMX slot completes")
    return "DMX512 logic-level, two packets, 128 us BREAK, 16 us MAB, 4 us bit cells, 25 slots each"


def compare(protocol, captures, handoff, sample_hz, aliases, i2c_target):
    require(math.isfinite(sample_hz) and sample_hz > 0, "Sample rate must be a positive finite number")
    if protocol == "reset":
        require(len(captures) == 1, "Reset requires one capture")
        with captures[0].open(encoding="utf-8-sig", newline="") as source:
            tested = read_trace(source, protocol, sample_hz, aliases)
        edges = tested.edges["pvm_reset_n"]
        require([level for _, level in edges] == [1, 0, 1], "Expected one active-low reset pulse and release")
        low_cycles = edges[2][0] - edges[1][0]
        require(low_cycles >= 16, f"Reset held low for only {low_cycles:g} core cycles")
        return [f"{captures[0].name}: reset asserted for {low_cycles:g} core cycles and released high"]
    require(len(captures) == len(REFERENCES[protocol]),
            "DMX512 requires two separate complete captures, one per load" if protocol == "dmx512"
            else f"{protocol} requires one capture")
    if protocol == "dmx512":
        require(captures[0].resolve() != captures[1].resolve(),
                "Provide distinct initial-load and reload capture files")
    results = []
    with ZipFile(handoff) as bundle:
        for capture, reference in zip(captures, REFERENCES[protocol]):
            with bundle.open(reference) as source:
                oracle = read_trace(io.TextIOWrapper(source, encoding="utf-8", newline=""),
                                    protocol, CORE_HZ, {})
            with capture.open(encoding="utf-8-sig", newline="") as source:
                tested = read_trace(source, protocol, sample_hz, aliases)
            if protocol == "i2c":
                result = check_i2c(tested, oracle, i2c_target)
            else:
                judge = {"uart": check_uart, "spi": check_spi, "dmx512": check_dmx}[protocol]
                result = judge(tested, oracle)
            results.append(f"{capture.name}: {result}")
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("protocol", choices=tuple(SIGNALS))
    parser.add_argument("captures", nargs="+", type=Path)
    parser.add_argument("--handoff", type=Path, default=DEFAULT_HANDOFF,
                        help="Arnav's PVM_Arty_A7_Handoff_b33a922.zip")
    parser.add_argument("--sample-hz", type=float, default=CORE_HZ,
                        help="ILA clock or external analyzer sample rate (default: 50 MHz)")
    parser.add_argument("--i2c-target", choices=("fixture", "board-fixture", "external"), default="fixture",
                        help="fixture checks exact timing, board-fixture checks sampled pad timing, "
                             "and external checks the bus transaction")
    parser.add_argument("--column", action="append", default=[], metavar="SIGNAL=HEADER[@BIT]",
                        help="Explicit CSV column alias, with optional LSB-based bit selector")
    args = parser.parse_args(argv)
    aliases = {}
    for assignment in args.column:
        name, delimiter, header = assignment.partition("=")
        key = name.casefold()
        if not delimiter or not key or not header or key in aliases:
            parser.error(f"Expected a single SIGNAL=HEADER assignment, got {assignment!r}")
        aliases[key] = header
    try:
        results = compare(args.protocol, args.captures, args.handoff, args.sample_hz,
                          aliases, args.i2c_target)
    except (OSError, KeyError, ValueError, csv.Error, BadZipFile) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    for result in results:
        print(f"PASS: {result}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
