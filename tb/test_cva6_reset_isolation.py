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

Three groups of tests, covering different parts of the problem:

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
- The stalled-target tests construct what CVA6 never produces on its own
  (measured: zero waiting cycles over 20000 park-loop cycles): an AW or AR
  still waiting for its ready when the reset lands, and a response that
  arrives while the core is isolated. The leg gate in tb/soc_dut.sv stops both
  of CVA6's fabric legs, like a target that has stopped answering, at phases
  across the park loop, so that the reset finds the bridge holding a request
  or a response outstanding. One test opens the gate during the reset, the
  other only after the restarted core has waited behind isolation. CVA6 keeps
  its response readies high even in reset, which would hide whether the bridge
  retires responses on its own, so these tests also hold them low while it is
  isolated, as an initiator may. Each check counts what it exercised and fails
  if that was nothing.
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
# Park-loop phases at which to engage the leg gate, in cycles after an AW
# handshake that goes ahead of its W. The loop repeats about every 120 cycles;
# depending on the phase the bridge holds an AR, an AW with its W, or nothing
# because the core is waiting on a response the gate keeps back. An AW is held
# for only 6 consecutive phases (measured: 110 to 115), so the step stays well
# below that and a shift of the loop by a few cycles cannot make the sweep miss
# it.
GATE_PHASES = range(0, 126, 3)
# Cycles the gate is engaged before ndmreset, so requests back up into the
# bridge. CVA6 stalls on the gate within five.
GATE_LEAD_CYCLES = 20
# Cycles the gate stays engaged after ndmreset is released, when the restarted
# core must wait behind isolation. The core enters debug mode and fetches again
# about 150 cycles after the release, so this leaves it waiting for the rest.
# ndmreset + lag stays well below the 1024-cycle isolation watchdog in soc_top.
GATE_LAG_CYCLES = 300
# Cycles after recovery in which the hart must complete an AXI read again.
RESUME_CYCLES = 200


async def _reset(dut):
    cocotb.start_soon(Clock(dut.clk_i, 20, unit="ns").start())
    dut.rst_ni.value = 0
    dut.dbg_force_core_req.value = 0
    dut.dbg_force_sba_req.value = 0
    dut.dbg_force_debug_req.value = 0
    dut.dbg_force_ndmreset.value = 0
    dut.dbg_cva6_gate.value = 0
    dut.dbg_cva6_hold_rsp_ready.value = 0
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


async def _wait_isolation_closed(dut, limit: int) -> int | None:
    """Return the cycles until CVA6's AXI isolation window is closed, or None after `limit`."""
    isolate = dut.i_soc_top.gen_platform.gen_cva6_core_path.cva6_isolate
    for cycle in range(limit):
        await RisingEdge(dut.clk_i)
        await ReadOnly()
        if not int(isolate.value):
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



class _IsolationMonitor:
    """Watch both sides of soc_axi_reset_bridge while CVA6 is isolated."""

    def __init__(self, dut) -> None:
        self.dut = dut
        path = dut.i_soc_top.gen_platform.gen_cva6_core_path
        self.isolate = path.cva6_isolate
        self.core_rst_n = dut.i_soc_top.gen_platform.core_rst_ni
        self.absorbed_b = 0  # fabric B valid cycles retired without the core
        self.absorbed_r = 0  # fabric R valid cycles retired without the core
        self.leaked = []  # responses the core saw while isolated
        self.blocked = 0  # requests the restarted core presented while isolated
        self.accepted = []  # requests accepted from the restarted core while isolated

    async def run(self) -> None:
        dut = self.dut
        cycle = 0
        while True:
            await RisingEdge(dut.clk_i)
            await ReadOnly()
            cycle += 1
            if not int(self.isolate.value):
                continue
            self.absorbed_b += int(dut.dbg_cva6_bridge_b_valid.value)
            self.absorbed_r += int(dut.dbg_cva6_bridge_r_valid.value)
            if int(dut.dbg_cva6_axi_b_valid.value) or int(dut.dbg_cva6_axi_r_valid.value):
                self.leaked.append(cycle)
            if int(self.core_rst_n.value):
                for ch in ("aw", "w", "ar"):
                    if int(getattr(dut, f"dbg_cva6_axi_{ch}_valid").value):
                        self.blocked += 1
                        if int(getattr(dut, f"dbg_cva6_axi_{ch}_ready").value):
                            self.accepted.append((cycle, ch))


async def _ndmreset_on_stalled_target(dut, release_gate_in_reset: bool) -> None:
    """Land ndmreset while the leg gate stalls CVA6's targets, at every GATE_PHASES phase.

    The gate is released halfway through ndmreset, or GATE_LAG_CYCLES after it
    when `release_gate_in_reset` is false. Every phase must bring the hart back
    into debug mode with isolation closed. CVA6's response readies are held low
    while it is isolated, so the responses that arrive then retire only if the
    bridge retires them.
    """
    await _reset(dut)
    await RisingEdge(dut.clk_i)
    dut.dbg_cva6_hold_rsp_ready.value = 1
    dut.dbg_force_debug_req.value = 1
    cycles = await _wait_debug_mode(dut, DEBUG_ENTRY_LIMIT)
    assert cycles is not None, "CVA6 never entered debug mode"

    bridge = dut.i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_reset_bridge
    monitor = _IsolationMonitor(dut)
    monitor_task = cocotb.start_soon(monitor.run())
    held_resets = {"aw": 0, "w": 0, "ar": 0}
    outstanding_resets = 0

    for phase in GATE_PHASES:
        await _wait_aw_without_w(dut)
        await RisingEdge(dut.clk_i)
        for _ in range(phase):
            await RisingEdge(dut.clk_i)
        dut.dbg_cva6_gate.value = 1
        for _ in range(GATE_LEAD_CYCLES):
            await RisingEdge(dut.clk_i)
        await ReadOnly()
        assert int(dut.dbg_cva6_gate_q.value), f"phase {phase}: the leg gate never engaged"
        held = [ch for ch in held_resets if int(getattr(bridge, f"{ch}_held_q").value)]
        outstanding = int(dut.dbg_cva6_outstanding_q.value)
        for ch in held:
            held_resets[ch] += 1
        outstanding_resets += outstanding > 0

        await RisingEdge(dut.clk_i)
        dut.dbg_force_ndmreset.value = 1
        if release_gate_in_reset:
            for _ in range(NDMRESET_CYCLES // 2):
                await RisingEdge(dut.clk_i)
            dut.dbg_cva6_gate.value = 0
            for _ in range(NDMRESET_CYCLES - NDMRESET_CYCLES // 2):
                await RisingEdge(dut.clk_i)
            dut.dbg_force_ndmreset.value = 0
        else:
            for _ in range(NDMRESET_CYCLES):
                await RisingEdge(dut.clk_i)
            dut.dbg_force_ndmreset.value = 0
            for _ in range(GATE_LAG_CYCLES):
                await RisingEdge(dut.clk_i)
            dut.dbg_cva6_gate.value = 0

        what = f"phase {phase} (held {held or 'nothing'}, {outstanding} outstanding)"
        cycles = await _wait_isolation_closed(dut, DEBUG_ENTRY_LIMIT)
        assert cycles is not None, (
            f"{what}: CVA6's AXI isolation window did not close within "
            f"{DEBUG_ENTRY_LIMIT} cycles of the last release"
        )
        assert await _wait_debug_mode(dut, DEBUG_ENTRY_LIMIT) is not None, (
            f"{what}: the hart did not re-enter debug mode within {DEBUG_ENTRY_LIMIT} cycles"
        )
        await RisingEdge(dut.clk_i)
        assert await _observe_axi_traffic(dut, RESUME_CYCLES), (
            f"{what}: the hart completed no AXI read within {RESUME_CYCLES} cycles of "
            "recovering"
        )
        dut._log.info("%s: isolation closed %d cycles after the last release", what, cycles)
        await RisingEdge(dut.clk_i)

    monitor_task.cancel()
    dut._log.info(
        "held at ndmreset: %s; resets with a response outstanding: %d; fabric responses "
        "retired during isolation: B %d, R %d cycles; requests from the restarted core "
        "held back: %d cycles",
        held_resets, outstanding_resets, monitor.absorbed_b, monitor.absorbed_r,
        monitor.blocked)

    assert not monitor.leaked, (
        f"the core saw a response while isolated, first at monitor cycle {monitor.leaked[0]}"
    )
    assert not monitor.accepted, (
        f"a request from the restarted core was accepted while isolated: {monitor.accepted[0]}"
    )
    # The checks that make the ones above mean something.
    for ch, count in held_resets.items():
        assert count, f"in no phase was the bridge holding {ch.upper()} when ndmreset landed"
    assert outstanding_resets, "no phase had a response outstanding when ndmreset landed"
    assert monitor.absorbed_b and monitor.absorbed_r, (
        "no B or no R response reached the bridge during isolation, so the masking "
        "toward the core was never exercised"
    )
    if not release_gate_in_reset:
        assert monitor.blocked, (
            "the restarted core presented no request while still isolated"
        )


@cocotb.test()
async def ndmreset_on_stalled_target_released_in_reset(dut):
    await _ndmreset_on_stalled_target(dut, release_gate_in_reset=True)


@cocotb.test()
async def ndmreset_on_stalled_target_released_after_reset(dut):
    await _ndmreset_on_stalled_target(dut, release_gate_in_reset=False)

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
