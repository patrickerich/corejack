"""CVA6 AXI reset isolation.

CVA6 is the only core that is itself the AXI initiator, so an ndmreset can
reset it while the crossbar and its targets keep running. Without an isolation
stage that outlives the core reset, a response the fabric has already accepted
is orphaned: nothing retires it, so it sits on the crossbar's slave port with
valid held and ready low, and can later land on the freshly restarted core.

The RV32 cores cannot hit this - their OBI buffers and obi-to-axi bridges sit
on rst_ni and own the fabric transaction - which is why this needs its own
target rather than riding on debug-sim (which builds no CVA6 RTL at all).

The check that matters is the *drain*: after ndmreset asserts, the fabric-side
R and B channels must go quiet within a bounded window. SBA access during
ndmreset is kept only as a secondary assertion, because the crossbar's
per-slave-port read paths are independent - SBA keeps working whether or not
the CVA6 leg is orphaned, so it cannot distinguish the two.

Scope, stated plainly: **this test does not construct the orphan condition.**
It measures zero fabric-side response activity after ndmreset, because the
reset synchroniser's delay exceeds the RAM response latency - every in-flight
response retires while CVA6 is still accepting it. Running this file against
the pre-isolation RTL produces identical numbers and passes, so it cannot tell
a working axi_isolate stage from its absence. What it does cover is that a real
CVA6 survives ndmreset without stalling the fabric or failing to restart, which
is worth having and did not exist before. Constructing the condition needs a
hook that stalls the target while the reset lands; see docs/open_items.md.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge

RAM_BASE = 0x8000_0000

# Cycles to let CVA6 run before forcing ndmreset, so it has fetches in flight.
WARMUP_CYCLES = 400
# Cycles the fabric-side response channels are allowed to stay stalled after
# ndmreset asserts. The memory round trip is under ten cycles, so anything
# still held after this is orphaned rather than merely in progress.
DRAIN_LIMIT = 64
# Total cycles to observe after asserting ndmreset.
OBSERVE_CYCLES = 400


async def _reset(dut):
    cocotb.start_soon(Clock(dut.clk_i, 20, unit="ns").start())
    dut.rst_ni.value = 0
    dut.dbg_force_core_req.value = 0
    dut.dbg_force_sba_req.value = 0
    dut.dbg_force_debug_req.value = 0
    dut.dbg_force_ndmreset.value = 0
    dut.dbg_instr_req.value = 0
    dut.dbg_instr_addr.value = 0
    dut.dbg_data_req.value = 0
    dut.dbg_data_we.value = 0
    dut.dbg_data_be.value = 0
    dut.dbg_data_addr.value = 0
    dut.dbg_data_wdata.value = 0
    dut.dbg_sba_req.value = 0
    dut.dbg_sba_we.value = 0
    dut.dbg_sba_be.value = 0
    dut.dbg_sba_addr.value = 0
    dut.dbg_sba_wdata.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(4):
        await RisingEdge(dut.clk_i)


async def _observe_axi_traffic(dut, cycles):
    """Run for `cycles` and report how many AR handshakes CVA6 completed."""
    handshakes = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if int(dut.dbg_cva6_axi_ar_valid.value) and int(dut.dbg_cva6_axi_ar_ready.value):
            handshakes += 1
    return handshakes


@cocotb.test()
async def ndmreset_with_axi_traffic_in_flight_drains_the_fabric(dut):
    await _reset(dut)

    # Precondition: CVA6 must actually be driving the fabric, otherwise the
    # drain check below passes vacuously. Nothing is preloaded into RAM, so the
    # core fetches whatever is there - that is enough to keep AR busy.
    handshakes = await _observe_axi_traffic(dut, WARMUP_CYCLES)
    assert handshakes > 0, (
        "CVA6 issued no AXI read requests during warm-up; the reset would land "
        "on an idle fabric and this test would prove nothing"
    )
    dut._log.info("warm-up: %d CVA6 AR handshakes before ndmreset", handshakes)

    # Leave the ReadOnly phase the sampling loop ended in before driving.
    await RisingEdge(dut.clk_i)

    # Land the reset on that traffic.
    dut.dbg_force_ndmreset.value = 1

    worst_r_stall = 0
    worst_b_stall = 0
    r_stall = 0
    b_stall = 0
    r_valid_cycles = 0
    b_valid_cycles = 0
    for _ in range(OBSERVE_CYCLES):
        await RisingEdge(dut.clk_i)
        await ReadOnly()

        r_valid_cycles += int(dut.dbg_cva6_fab_r_valid.value)
        b_valid_cycles += int(dut.dbg_cva6_fab_b_valid.value)

        if int(dut.dbg_cva6_fab_r_valid.value) and not int(dut.dbg_cva6_fab_r_ready.value):
            r_stall += 1
            worst_r_stall = max(worst_r_stall, r_stall)
        else:
            r_stall = 0

        if int(dut.dbg_cva6_fab_b_valid.value) and not int(dut.dbg_cva6_fab_b_ready.value):
            b_stall += 1
            worst_b_stall = max(worst_b_stall, b_stall)
        else:
            b_stall = 0

    dut._log.info(
        "post-ndmreset worst stall: R=%d cycles, B=%d cycles (limit %d); "
        "fabric response activity: r_valid %d cycles, b_valid %d cycles",
        worst_r_stall, worst_b_stall, DRAIN_LIMIT, r_valid_cycles, b_valid_cycles,
    )

    assert worst_r_stall < DRAIN_LIMIT, (
        f"fabric read response to CVA6 stalled {worst_r_stall} cycles during "
        f"ndmreset: the crossbar is holding a response nothing will retire"
    )
    assert worst_b_stall < DRAIN_LIMIT, (
        f"fabric write response to CVA6 stalled {worst_b_stall} cycles during "
        f"ndmreset: the crossbar is holding a response nothing will retire"
    )

    # Secondary: the debug path still reaches RAM while the core is held down.
    await RisingEdge(dut.clk_i)
    dut.dbg_force_sba_req.value = 1
    dut.dbg_sba_addr.value = RAM_BASE
    dut.dbg_sba_be.value = 0xF
    dut.dbg_sba_we.value = 1
    dut.dbg_sba_wdata.value = 0x5A5A_4321
    dut.dbg_sba_req.value = 1
    for _ in range(64):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if int(dut.i_soc_top.gen_platform.sba_gnt.value):
            break
    else:
        raise AssertionError("SBA write was never granted during ndmreset")
    await RisingEdge(dut.clk_i)
    dut.dbg_sba_req.value = 0
    dut.dbg_force_sba_req.value = 0

    # Release the reset and confirm the core comes back and drives the fabric.
    dut.dbg_force_ndmreset.value = 0
    for _ in range(64):
        await RisingEdge(dut.clk_i)
    restarted = await _observe_axi_traffic(dut, WARMUP_CYCLES)
    assert restarted > 0, (
        "CVA6 issued no AXI read requests after ndmreset was released; the core "
        "did not restart cleanly"
    )
    dut._log.info("post-release: %d CVA6 AR handshakes", restarted)
