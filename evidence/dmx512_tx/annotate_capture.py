"""Summarize author P5 captures against the image's nominal waveform."""

from bisect import bisect_right
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
BIT_CLOCKS = 200
SLOT_CLOCKS = 11 * BIT_CLOCKS
PAYLOAD = (0x00, *([0xA5] * 24))


def summarize(path, first_mab, interval):
    with path.open(newline="") as stream:
        rows = [(int(row["core_cycle"]), int(row["p5"])) for row in csv.DictReader(stream)]
    assert rows[0] == (0, 1)
    assert all(a < b and v != w for (a, v), (b, w) in zip(rows, rows[1:]))
    breaks = [(start, end) for (start, level), (end, _) in zip(rows, rows[1:])
              if level == 0 and end - start > 4_600]
    assert len(breaks) == 2, path
    assert breaks[1][0] - breaks[0][0] == interval
    clock_points = [cycle for cycle, _ in rows]

    def level_at(cycle):
        return rows[bisect_right(clock_points, cycle) - 1][1]

    packets = []
    expected_edges = [(0, 1)]
    timeline = []

    def change(cycle, level):
        if expected_edges[-1][1] != level:
            expected_edges.append((cycle, level))

    def region(number, kind, start, end, value=""):
        timeline.append((number, kind, start, end, value))

    for number, (start, end) in enumerate(breaks, start=1):
        assert end - start == 6_400
        mab_end = rows[clock_points.index(end) + 1][0]
        assert mab_end - end == (first_mab if number == 1 else 800)
        change(start, 0)
        change(end, 1)
        region(number, "BREAK", start, end)
        region(number, "MAB", end, mab_end)
        decoded = []
        for slot, expected in enumerate(PAYLOAD):
            begin = mab_end + slot * SLOT_CLOCKS
            cells = [level_at(begin + BIT_CLOCKS * bit + BIT_CLOCKS // 2) for bit in range(11)]
            assert cells[0] == 0 and cells[9:] == [1, 1]
            decoded.append(sum(cells[bit + 1] << bit for bit in range(8)))
            bits = (0, *((expected >> bit) & 1 for bit in range(8)), 1, 1)
            for bit, level in enumerate(bits):
                change(begin + bit * BIT_CLOCKS, level)
            region(number, f"slot {slot}", begin, begin + SLOT_CLOCKS, f"0x{decoded[-1]:02X}")
        assert tuple(decoded) == PAYLOAD
        packet_end = mab_end + 25 * SLOT_CLOCKS
        packets.append({
            "break_start": start,
            "break_end": end,
            "mab_end": mab_end,
            "packet_end": packet_end,
            "decoded_bytes": [f"{byte:02X}" for byte in decoded],
        })

    assert rows == expected_edges, f"Unexpected transition in {path}"
    return rows, packets, timeline


def plot(runs):
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(3, 1, figsize=(10, 6.4), layout="constrained")
    fig.suptitle("DMX512 TX on P5 · frozen RTL b33a922", fontweight="bold")
    colors = {"positive": "#174C73", "short_mab": "#B74D2A"}
    for name, (rows, packets, _) in runs.items():
        origin = packets[0]["break_start"]
        times = [(cycle - origin) / 50 for cycle, _ in rows]
        levels = [level for _, level in rows]
        times.append(2580)
        levels.append(1)
        if name == "positive":
            axes[0].step(times, levels, where="post", color=colors[name], linewidth=0.9)
            axes[0].set_xlim(-15, 2570)
        axes[1].step(times, levels, where="post", color=colors[name], linewidth=1.4,
                     linestyle="--" if name == "short_mab" else "-",
                     label="First MAB 8 µs (mutant)" if name == "short_mab" else "First MAB 16 µs")
    axes[0].set_title("Two packets · 00 + 24 × A5 per packet · 1,280 µs between BREAKs")
    axes[0].axvline(1280, color="#B74D2A", linewidth=0.8, alpha=0.8)
    axes[1].set_title("First BREAK and MAB")
    axes[1].set_xlim(-8, 175)
    axes[1].legend(loc="upper center", bbox_to_anchor=(0.34, 0.98), frameon=False)
    rows, packets, _ = runs["positive"]
    slot_start = packets[0]["mab_end"] + SLOT_CLOCKS
    slot_edges = [(cycle, level) for cycle, level in rows
                  if slot_start <= cycle < slot_start + SLOT_CLOCKS]
    slot_edges.append((slot_start + SLOT_CLOCKS, 1))
    axes[2].step([(cycle - slot_start) / 50 for cycle, _ in slot_edges],
                 [level for _, level in slot_edges], where="post", color=colors["positive"])
    axes[2].set_xlim(0, 44)
    axes[2].set_xticks(range(0, 45, 4))
    axes[2].set_title("First data slot · A5 LSB first · 4 µs per bit, 8 µs stop")
    for axis in axes:
        axis.set_ylim(-0.25, 1.35)
        axis.set_yticks((0, 1), ("SPACE", "MARK"))
        axis.set_xlabel("Elapsed time (µs)")
        axis.grid(axis="x", color="#E1E7EB")
    fig.savefig(ROOT / "dmx512_waveform.png", dpi=180)
    plt.close(fig)


if __name__ == "__main__":
    first_runs = {}
    summary = {}
    for name, first_mab, interval in (("positive", 800, 64000), ("short_mab", 400, 63600)):
        summary[name] = []
        for run in (1, 2):
            captured = summarize(ROOT / name / f"run_{run}_p5.csv", first_mab, interval)
            rows, packets, timeline = captured
            if run == 1:
                first_runs[name] = captured
            with (ROOT / name / f"run_{run}_annotated.csv").open("w", newline="") as file:
                writer = csv.writer(file, lineterminator="\n")
                writer.writerow(("packet", "region", "start_cycle", "end_cycle", "decoded_byte"))
                writer.writerows(timeline)
            summary[name].append(packets)
            print(f"{name} run {run}: 2 packets, [00, A5 × 24] each, "
                  f"128 us BREAKs, {first_mab/50:g}/16 us MABs, "
                  f"{interval/50:g} us BREAK-to-BREAK, 4 us bits")
    (ROOT / "waveform_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    plot(first_runs)
