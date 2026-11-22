"""Directed engine and FIFO lockstep with stimuli sent through the RTL wrapper."""

import csv
import json
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.task import bridge
from cocotb.triggers import FallingEdge, Timer, with_timeout

from demo_replay import trace_values
from tb_rtl.pvm_trace_jobs import FIELDS
from test_toolchain import SimTransport
from tools.pvm_asm import assemble
from tools.pvm_host import DONE, PVMHost
from tools.pvm_image import build_image
from tools.pvm_iss import Engine, Fault, Inputs, State

BRANCHES = """
    set x, 2
again:
    jmp x--, again
    jmp !x, bad
    jmp pin, bad
    wait 1 pin 12 side 1 [2]
    jmp pin, check_osr side 1
bad:
    evt done
check_osr:
    jmp !osre, bad side 1
    pull block side 1
    jmp !osre, finish side 1
    jmp bad
finish:
    evt done side 1
"""

WIDE_FIFO = """
    pull block
    out x, 0
    mov isr, x
    push block
    mov isr, x
    push block
    mov isr, x
    push block
    evt done
"""

SHIFTS = """
    pull block
    out x, 4
    in x, 4
    out y, 8
    in y, 8
    push block
    pull block
    out x, 0
    in x, 0
    push block
    evt done
"""

NARROW_FIFO = """
    set x, 21
    pull noblock
    out x, 8
    mov isr, x
    push iffull noblock
    set y, 4
again:
    in x, 8
    push noblock
    jmp y--, again
    evt done
"""

EXTRA_FIELDS = (
    "x", "y", "osr", "isr", "osr_count", "isr_count", "tx_level", "rx_level",
    "pin_in", "host_tx_push", "host_tx_data", "host_rx_pop",
)


async def compare_engine(dut, image, name):
    engine = Engine.from_image(image)
    top = dut.user_project.pvm
    while True:
        await FallingEdge(dut.clk)
        if int(top.enable_pulse.value):
            break
    await FallingEdge(dut.clk)
    directory = Path("output") / "iss_lockstep" / name
    directory.mkdir(parents=True, exist_ok=True)
    seen = set()
    stalled_at = set()
    tx_pops = []
    rx_pushes = []
    last_fab_write = False
    with (directory / "iss.csv").open("w", newline="") as left, \
         (directory / "rtl.csv").open("w", newline="") as right:
        iss, rtl = [csv.writer(stream, lineterminator="\n") for stream in (left, right)]
        for writer in (iss, rtl):
            writer.writerow((*FIELDS, *EXTRA_FIELDS))
        for cycle in range(10_000):
            if name == "wait_branches" and cycle == 80:
                dut.uio_in.value = 1
            host_push = int(top.tx_push.value)
            host_pop = int(top.rx_pop.value)
            stimulus = (int(top.pin_in.value), host_push,
                        int(top.tx_data.value) if host_push else 0, host_pop)
            inputs = Inputs(pins=stimulus[0])
            before = (int(engine.state), engine.pc, int(engine.pc in engine.words),
                      engine.out_val, engine.oe_val, engine.fab_ctrl, int(last_fab_write))
            expected_regs = (engine.x, engine.y, engine.osr, engine.isr,
                             engine.osr_count, engine.isr_count, len(engine.tx), len(engine.rx))
            seen.add(engine.pc)
            if engine.stalled:
                stalled_at.add((engine.pc, len(engine.tx), len(engine.rx)))

            effects = engine.step(inputs)
            last_fab_write = effects.fab_write
            if effects.tx_pop:
                tx_pops.append(cycle)
            if effects.rx_byte is not None:
                rx_pushes.append((cycle, effects.rx_byte))
            expected = (*before, int(effects.tx_pop), int(effects.rx_byte is not None),
                        effects.rx_byte or 0, 0, int(Fault.NONE), *expected_regs, *stimulus)
            unit = top.engine
            actual = (*trace_values(top), int(unit.x_q.value), int(unit.y_q.value),
                      int(unit.osr_q.value), int(unit.isr_q.value), int(unit.osr_cnt_q.value),
                      int(unit.isr_cnt_q.value), int(top.tx_level.value), int(top.rx_level.value),
                      *stimulus)
            iss.writerow((cycle, *expected))
            rtl.writerow((cycle, *actual))
            differences = [(field, exp, got) for field, exp, got in
                           zip((*FIELDS[1:], *EXTRA_FIELDS), expected, actual) if exp != got]
            assert not differences, f"{name} cycle {cycle} pins {inputs.pins:#07x}: {differences}"

            # Host transactions take effect at the same edge as the engine.
            # These vectors schedule host stimuli away from an engine FIFO beat.
            if host_push:
                assert not effects.tx_pop and len(engine.tx) < 4
                engine.tx.append(stimulus[2])
            if host_pop:
                assert effects.rx_byte is None and engine.rx
                engine.rx.popleft()
            await FallingEdge(dut.clk)
            if engine.state != State.RUN:
                assert engine.state == State.DONE and int(top.eng_done_req.value)
                assert engine.fault_pc == max(engine.words)
                break
        else:
            raise AssertionError(f"{name} exceeded 10000 core cycles")
    summary = {"cycles": engine.cycle, "pcs": sorted(seen),
               "stalled_at_pc_tx_rx": sorted(stalled_at), "tx_pop_cycles": tx_pops,
               "rx_pushes": rx_pushes, "final_rx": list(engine.rx)}
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


@cocotb.test()
async def directed_engine_lockstep(dut):
    dut.ena.value = 1
    dut.ui_in.value = 2
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    transport = SimTransport(dut)
    host = PVMHost(transport)
    await transport.wait_cycles(4)
    dut.rst_n.value = 1
    await transport.wait_cycles(4)

    scenarios = (
        ("wait_branches", BRANCHES, {0x100: 3, 0x107: 5, 0x108: 1, 0x109: 12}, (), b""),
        ("wide_fifo", WIDE_FIFO, {0x100: 4, 0x10C: 17}, (0x34,), b"\x34\x12\x34\x12"),
        ("shifts_left", SHIFTS, {0x100: 2, 0x10C: 16}, (0x34, 0x12, 0xA5, 0xC3), b"\x23\x01\xA5\xC3"),
        ("shifts_right", SHIFTS, {0x100: 2, 0x10C: 19}, (0x34, 0x12, 0xA5, 0xC3), b"\x40\x23\xA5\xC3"),
        ("narrow_fifo", NARROW_FIFO, {0x100: 2, 0x10C: 1}, (), bytes([21] * 4)),
    )
    for version, (name, source, config, preload, rx) in enumerate(scenarios, start=1):
        dut.uio_in.value = 0
        words = assemble(source, side_count=config.get(0x108, 0))
        image = build_image(words, config=config, image_version=version, tx_preload=preload)
        assert (await bridge(host.load_image)(image))["status"] == 0x42
        comparison = cocotb.start_soon(compare_engine(dut, image, name))
        await bridge(host.command)(0x03)
        if name in {"wait_branches", "wide_fifo"}:
            await Timer(20, unit="us")
            await bridge(host.push_tx)((0xA5 if name == "wait_branches" else 0x12,))
        if name == "wide_fifo":
            await Timer(5, unit="us")
            assert await bridge(host.pop_rx)(1) == b"\x34"
            await Timer(5, unit="us")
            assert await bridge(host.pop_rx)(1) == b"\x12"
        summary = await with_timeout(comparison, 300, "us")
        terminal = await bridge(host.wait_done)(polls=8)
        assert terminal["state"] == DONE and terminal["fault_pc"] == max(words)
        assert bytes(summary["final_rx"]) == rx
        assert await bridge(host.pop_rx)(len(rx)) == rx
        if name == "wait_branches":
            assert (4, 0, 0) in summary["stalled_at_pc_tx_rx"]
            assert (8, 0, 0) in summary["stalled_at_pc_tx_rx"]
            assert 6 not in summary["pcs"] and 10 not in summary["pcs"]
        if name == "wide_fifo":
            assert (0, 1, 0) in summary["stalled_at_pc_tx_rx"]
            assert {(7, 0, 4), (7, 0, 3)} <= set(summary["stalled_at_pc_tx_rx"])
            assert len(summary["tx_pop_cycles"]) == 2
            assert len(summary["rx_pushes"]) == 6
        if name == "narrow_fifo":
            assert not summary["tx_pop_cycles"] and len(summary["rx_pushes"]) == 4
        dut._log.info("%s matched %d cycles; RX %s", name, summary["cycles"], rx.hex(" "))
