"""soc_mem_ss throughput benchmark.

Sweeps the number of active init ports (1/2/4) against three access patterns
(disjoint banks / same bank / random) and reports aggregate words/cycle. The
qualitative assertions prove the property that motivates the multi-port memory
direction: with disjoint banks, throughput scales with the number of active
init ports, whereas same-bank traffic is capped at one slice's rate no matter
how many ports drive it.

Absolute numbers reflect the subsystem at its default outstanding depths
(per-port ingress = 2 / egress = 8, slice in = 2 / out = 4), which are sized so
neither a port nor a bank is the limiter: a single port sustains ~1 access per
cycle, and so does a single slice under any number of ports. The floors below
are set accordingly, and the scaling *ratios* are what matter beyond them.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

PATTERN_DISJOINT = 0
PATTERN_SAME_BANK = 1
PATTERN_RANDOM = 2
PATTERN_NAME = {0: "disjoint", 1: "same-bank", 2: "random"}

BUDGET = 256
MAX_WAIT = 300_000


async def reset_dut(dut):
    dut.start_i.value = 0
    dut.pattern_i.value = 0
    dut.we_i.value = 0
    dut.budget_i.value = 0
    dut.active_mask_i.value = 0
    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def run_bench(dut, *, pattern, active_ports, budget=BUDGET, we=0):
    mask = (1 << active_ports) - 1
    dut.pattern_i.value = pattern
    dut.active_mask_i.value = mask
    dut.budget_i.value = budget
    dut.we_i.value = we

    dut.start_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.start_i.value = 0

    for _ in range(MAX_WAIT):
        await RisingEdge(dut.clk_i)
        if int(dut.done_o.value) == 1:
            break
    else:
        raise AssertionError("benchmark run never asserted done_o")

    cycles = int(dut.cycles_o.value)
    accesses = int(dut.accesses_o.value)
    timeout = int(dut.timeout_o.value)
    errs = int(dut.err_count_o.value)
    thru = accesses / cycles if cycles else 0.0

    dut._log.info(
        "pattern=%-9s ports=%d  accesses=%5d  cycles=%5d  words/cycle=%.3f%s"
        % (PATTERN_NAME[pattern], active_ports, accesses, cycles, thru,
           "  TIMEOUT" if timeout else "")
    )

    assert timeout == 0, "benchmark timed out (possible hang)"
    assert errs == 0, f"unexpected init_err responses: {errs}"
    assert accesses == active_ports * budget, (
        f"expected {active_ports * budget} accesses, got {accesses}")
    return thru


@cocotb.test()
async def mem_ss_throughput(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    results = {}
    for pattern in (PATTERN_DISJOINT, PATTERN_SAME_BANK, PATTERN_RANDOM):
        for ports in (1, 2, 4):
            results[(pattern, ports)] = await run_bench(
                dut, pattern=pattern, active_ports=ports)

    # A write run, to confirm the write direction is equally concurrent.
    wr4 = await run_bench(dut, pattern=PATTERN_DISJOINT, active_ports=4, we=1)

    d1 = results[(PATTERN_DISJOINT, 1)]
    d2 = results[(PATTERN_DISJOINT, 2)]
    d4 = results[(PATTERN_DISJOINT, 4)]
    s1 = results[(PATTERN_SAME_BANK, 1)]
    s4 = results[(PATTERN_SAME_BANK, 4)]

    dut._log.info(
        "summary: disjoint 1/2/4 ports = %.2f / %.2f / %.2f words/cycle; "
        "same-bank 1/4 = %.2f / %.2f; disjoint-write 4 = %.2f"
        % (d1, d2, d4, s1, s4, wr4)
    )

    # A single pipelined port sustains ~1 access/cycle: the per-port egress
    # depth covers the reorder-buffer slot round trip, so the subsystem does not
    # throttle an initiator that keeps requests in flight.
    assert d1 > 0.9, f"single-port disjoint throughput below ~1/cycle: {d1:.3f}"
    # Disjoint banks: throughput scales with active ports (multi-bank concurrency).
    assert d4 > 3.5, f"4-port disjoint throughput did not scale: {d4:.3f}"
    assert d4 > 3.5 * d1, (
        f"4-port disjoint ({d4:.3f}) did not beat single-port ({d1:.3f}) ~linearly")
    assert d2 > 1.8 * d1, f"2-port disjoint ({d2:.3f}) did not scale over 1-port ({d1:.3f})"
    # Same bank is the serialization floor: one slice caps at its own rate - now
    # ~1 access/cycle - no matter how many ports pile onto it.
    assert s4 < 1.1, f"same-bank throughput exceeded one slice's ceiling: {s4:.3f}"
    assert s1 > 0.9, f"single-port same-bank throughput below one slice's rate: {s1:.3f}"
    assert d4 > 3.5 * s4, (
        f"banked concurrency ({d4:.3f}) did not beat single-bank serialization ({s4:.3f})")
    # Writes are as concurrent as reads.
    assert wr4 > 3.5, f"4-port disjoint write throughput did not scale: {wr4:.3f}"
