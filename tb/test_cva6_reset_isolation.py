"""CVA6 AXI reset isolation.

CVA6 is the only core that is itself the AXI initiator, so an ndmreset can
reset it while the fabric keeps running. Without an isolation stage that
outlives the core reset, a response the fabric has already accepted is
orphaned: nothing retires it, so it sits on the fabric-side port with valid
held and ready low, and can later land on the freshly restarted core. CVA6 has
two fabric-side legs - the crossbar's slave port 0 for non-RAM traffic and a
dedicated soc_axi_to_mem for the RAM window - and both are watched here.

The RV32 cores cannot hit this - their OBI buffers and obi-to-axi bridges sit
on rst_ni and own the fabric transaction - which is why this needs its own
target rather than riding on debug-sim (which builds no CVA6 RTL at all).

The check that matters is the *drain*: after ndmreset asserts, the fabric-side
R and B channels must go quiet within a bounded window. SBA access during
ndmreset is kept only as a secondary assertion, because the crossbar's
per-slave-port read paths are independent - SBA keeps working whether or not
the CVA6 leg is orphaned, so it cannot distinguish the two.

Two tests, covering different halves of the problem:

- The traffic test does **not** construct an orphaned response. It measures
  zero fabric-side response activity after ndmreset, because the reset
  synchroniser's delay exceeds the RAM response latency - every in-flight
  response retires while CVA6 is still accepting it. What it covers is that a
  real CVA6 survives ndmreset without stalling the fabric or failing to restart.
- The torn-write test **does** construct a torn request. A halted hart's park
  loop stores to the debug module on every pass, and CVA6's AXI shim has its AW
  accepted one cycle before its W. ndmreset landing in that gap used to drop W
  before its handshake, so the write never completed, the isolation stage never
  drained, and the hart never halted again (the intermittent "Hart 0 failed to
  halt" seen on the AXKU5). soc_axi_reset_bridge now holds that W. The
  protocol checkers on the fabric side are part of the check: their $error ends
  the simulation.

Not constructed here, because CVA6 never produces them on its own (measured:
zero waiting cycles over 20000 park-loop cycles): an AW or AR still waiting for
its ready when the reset lands, and a response still stalled toward the core.
Both need a hook that stalls the target while the reset lands; see
docs/source/open_items.rst.
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
# Torn writes to construct back to back, so a counter left off by one by the
# first one shows up as a hang on a later one.
TORN_WRITE_RESETS = 3
# Cycles ndmreset is held, as a debugger pulse would be.
NDMRESET_CYCLES = 50
# Cycles to wait for the hart to (re-)enter debug mode. It takes about 150
# after an ndmreset release.
DEBUG_ENTRY_LIMIT = 5000
# Park-loop cycles to search for the AW-without-W gap. It opens about once
# every 120 cycles.
GAP_SEARCH_LIMIT = 20000


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


async def _wait_debug_mode(dut, limit: int) -> int | None:
    """Return the cycles until CVA6 is in debug mode, or None after `limit`."""
    for cycle in range(limit):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if int(dut.dbg_cva6_debug_mode.value):
            return cycle
    return None


async def _wait_aw_without_w(dut) -> int:
    """Wait for a cycle whose AW handshake completes without its W; return the address.

    Returns in that cycle's ReadOnly phase, before the handshake edge.
    """
    for _ in range(GAP_SEARCH_LIMIT):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        aw = int(dut.dbg_cva6_axi_aw_valid.value) and int(dut.dbg_cva6_axi_aw_ready.value)
        w = int(dut.dbg_cva6_axi_w_valid.value) and int(dut.dbg_cva6_axi_w_ready.value)
        if aw and not w:
            return int(dut.dbg_cva6_axi_aw_addr.value)
    raise AssertionError(
        f"no AW handshake without its W in {GAP_SEARCH_LIMIT} park-loop cycles; "
        "the torn-write condition was not constructed"
    )


@cocotb.test()
async def ndmreset_between_aw_and_w_recovers_the_hart(dut):
    await _reset(dut)
    await RisingEdge(dut.clk_i)
    # Held throughout, like OpenOCD's `reset halt`: haltreq stays set across
    # ndmreset, so the hart must come back into debug mode after each release.
    dut.dbg_force_debug_req.value = 1
    cycles = await _wait_debug_mode(dut, DEBUG_ENTRY_LIMIT)
    assert cycles is not None, "CVA6 never entered debug mode"

    isolate = dut.i_soc_top.gen_platform.gen_cva6_core_path.cva6_isolate
    for n in range(1, TORN_WRITE_RESETS + 1):
        addr = await _wait_aw_without_w(dut)
        # The AW handshake completes on this edge; the reset lands right after
        # it, with the W still owed.
        await RisingEdge(dut.clk_i)
        dut.dbg_force_ndmreset.value = 1
        for _ in range(NDMRESET_CYCLES):
            await RisingEdge(dut.clk_i)
        dut.dbg_force_ndmreset.value = 0

        cycles = await _wait_debug_mode(dut, DEBUG_ENTRY_LIMIT)
        assert cycles is not None, (
            f"torn write {n} (AW to {addr:#x} accepted, W not): the hart did not "
            f"re-enter debug mode within {DEBUG_ENTRY_LIMIT} cycles of ndmreset "
            f"release (cva6_isolate={isolate.value})"
        )
        assert not int(isolate.value), (
            f"torn write {n}: CVA6 is back in debug mode but its AXI isolation "
            "window never closed"
        )
        dut._log.info("torn write %d (AW to %#x): debug mode %d cycles after release",
                      n, addr, cycles)
        await RisingEdge(dut.clk_i)


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

    # One (valid, ready) handle pair per response channel per fabric-side leg.
    legs = {
        "xbar R": (dut.dbg_cva6_fab_r_valid, dut.dbg_cva6_fab_r_ready),
        "xbar B": (dut.dbg_cva6_fab_b_valid, dut.dbg_cva6_fab_b_ready),
        "ram R": (dut.dbg_cva6_ram_r_valid, dut.dbg_cva6_ram_r_ready),
        "ram B": (dut.dbg_cva6_ram_b_valid, dut.dbg_cva6_ram_b_ready),
    }
    worst_stall = {name: 0 for name in legs}
    stall = {name: 0 for name in legs}
    valid_cycles = {name: 0 for name in legs}
    for _ in range(OBSERVE_CYCLES):
        await RisingEdge(dut.clk_i)
        await ReadOnly()

        for name, (valid_h, ready_h) in legs.items():
            valid = int(valid_h.value)
            valid_cycles[name] += valid
            if valid and not int(ready_h.value):
                stall[name] += 1
                worst_stall[name] = max(worst_stall[name], stall[name])
            else:
                stall[name] = 0

    dut._log.info(
        "post-ndmreset worst stall (limit %d): %s; fabric response activity: %s",
        DRAIN_LIMIT,
        ", ".join(f"{name}={worst_stall[name]}" for name in legs),
        ", ".join(f"{name} valid {valid_cycles[name]} cycles" for name in legs),
    )

    for name in legs:
        assert worst_stall[name] < DRAIN_LIMIT, (
            f"{name} response to CVA6 stalled {worst_stall[name]} cycles during "
            f"ndmreset: the fabric is holding a response nothing will retire"
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
