"""Core-only reset on the cores that reset synchronously.

An ndmreset resets the core while the bus side keeps running. SERV and
PicoRV32 reset synchronously, so they hold a bus request until the clock edge
after the reset asserts. Their adapters track the access in flight with flops
that reset asynchronously, so for that one cycle the adapter no longer knows
the request was already accepted. Unless the adapter withholds it, the bus
side accepts the same request a second time: harmless for RAM, but a repeated
write or a repeated read with side effects on a peripheral.

The test loads a short loop of one store and one load into RAM, then lands an
ndmreset at each of the first cycles after a fetch, a load and a store is
accepted. The check is that the bus side accepts nothing from a core that is
in reset. Each kind of access counts the resets that found it in flight, and
the test fails if that was none.
"""

from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, RisingEdge

RAM_BASE = 0x8000_0000
BOOT_ADDR = RAM_BASE + 0x80

# lui x2, 0x80001 ; loop: sw x0, 0(x2) ; lw x1, 0(x2) ; jal x0, loop
PROGRAM = (0x8000_1137, 0x0001_2023, 0x0001_2083, 0xFF9F_F06F)

# Cycles after an access is accepted at which ndmreset asserts. Zero is the
# cycle right after the handshake, when the access is always still in flight.
RESET_DELAYS = range(4)
# Cycles ndmreset is held. Longer than any response takes, so a restarted core
# never sees a response to an access from before the reset.
NDMRESET_CYCLES = 20
# Cycles to wait for one access of a kind. SERV takes about 40 per instruction.
ACCESS_LIMIT = 2000
# Cycles to wait for the first fetch after ndmreset is released.
RESTART_LIMIT = 200
# Cycles to wait for one handshake while loading the program.
LOAD_LIMIT = 64


async def _wait_for_signal(clk, signal, cycles):
    for _ in range(cycles):
        await RisingEdge(clk)
        await ReadOnly()
        if int(signal.value):
            return
    raise AssertionError(f"Timed out waiting for {signal._path}")


async def _reset_and_load(dut):
    """Reset the platform and load PROGRAM, leaving the core in ndmreset."""
    cocotb.start_soon(Clock(dut.clk_i, 20, unit="ns").start())
    p = dut.i_soc_top.gen_platform
    dut.rst_ni.value = 0
    dut.dbg_force_core_req.value = 0
    dut.dbg_force_sba_req.value = 0
    dut.dbg_force_debug_req.value = 0
    # Held from the start: on empty RAM PicoRV32 would trap and stop.
    dut.dbg_force_ndmreset.value = 1
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

    # Write the program through the core's own data port, which the core in
    # reset leaves idle.
    dut.dbg_force_core_req.value = 1
    dut.dbg_data_we.value = 1
    dut.dbg_data_be.value = 0xF
    for index, word in enumerate(PROGRAM):
        dut.dbg_data_addr.value = BOOT_ADDR + 4 * index
        dut.dbg_data_wdata.value = word
        dut.dbg_data_req.value = 1
        await _wait_for_signal(dut.clk_i, p.data_gnt, LOAD_LIMIT)
        await RisingEdge(dut.clk_i)
        dut.dbg_data_req.value = 0
        await _wait_for_signal(dut.clk_i, p.data_rvalid, LOAD_LIMIT)
        await RisingEdge(dut.clk_i)
    dut.dbg_data_we.value = 0
    dut.dbg_force_core_req.value = 0


class _Socket:
    """Samples the core's bus socket once per cycle.

    The values sampled after a clock edge are the ones the next edge acts on,
    so a request and grant seen together are a handshake at the next edge.
    """

    def __init__(self, dut):
        self.dut = dut
        self.p = dut.i_soc_top.gen_platform
        self.cycles = 0
        # Kinds of access accepted at the edge that ends the sampled cycle.
        self.accepted = set()
        self.fetch_addr = 0
        # Accesses accepted and not yet answered, oldest first.
        self.fetches = deque()
        self.data = deque()
        self.accepted_in_reset = []

    def in_flight(self, kind: str) -> bool:
        return kind in self.fetches or kind in self.data

    async def cycle(self, ndmreset: int | None = None) -> None:
        """Advance one clock edge, changing ndmreset right after it if given."""
        await RisingEdge(self.dut.clk_i)
        if ndmreset is not None:
            self.dut.dbg_force_ndmreset.value = ndmreset
        await ReadOnly()
        p = self.p
        self.cycles += 1
        if int(p.instr_rvalid.value) and self.fetches:
            self.fetches.popleft()
        if int(p.data_rvalid.value) and self.data:
            self.data.popleft()

        self.accepted = set()
        if int(p.instr_req.value) and int(p.instr_gnt.value):
            self.accepted.add("fetch")
            self.fetch_addr = int(p.instr_addr.value)
            self.fetches.append("fetch")
        if int(p.data_req.value) and int(p.data_gnt.value):
            kind = "store" if int(p.data_we.value) else "load"
            self.accepted.add(kind)
            self.data.append(kind)
        if self.accepted and not int(p.core_rst_ni.value):
            kinds = "+".join(sorted(self.accepted))
            self.accepted_in_reset.append(f"{kinds} in cycle {self.cycles}")


async def _run_until(sock: _Socket, kind: str) -> None:
    for _ in range(ACCESS_LIMIT):
        await sock.cycle()
        if kind in sock.accepted:
            return
    raise AssertionError(f"the core made no {kind} in {ACCESS_LIMIT} cycles")


async def _wait_restart(sock: _Socket) -> None:
    for _ in range(RESTART_LIMIT):
        await sock.cycle()
        if "fetch" in sock.accepted:
            assert sock.fetch_addr == BOOT_ADDR, (
                f"first fetch after the reset went to 0x{sock.fetch_addr:08x}"
            )
            return
    raise AssertionError(f"the core did not restart within {RESTART_LIMIT} cycles")


@cocotb.test()
async def core_in_reset_repeats_no_access(dut):
    await _reset_and_load(dut)
    sock = _Socket(dut)
    await sock.cycle(ndmreset=0)
    await _wait_restart(sock)

    found_in_flight = {"fetch": 0, "load": 0, "store": 0}
    for kind in found_in_flight:
        for delay in RESET_DELAYS:
            await _run_until(sock, kind)
            for _ in range(delay):
                await sock.cycle()
            found_in_flight[kind] += sock.in_flight(kind)
            await sock.cycle(ndmreset=1)
            for _ in range(NDMRESET_CYCLES - 1):
                await sock.cycle()
            await sock.cycle(ndmreset=0)
            await _wait_restart(sock)

    dut._log.info("resets that found an access in flight: %s", found_in_flight)
    assert not sock.accepted_in_reset, (
        "the bus side accepted a request from the core in reset: "
        + ", ".join(sock.accepted_in_reset)
    )
    for kind, count in found_in_flight.items():
        assert count, f"no reset found a {kind} in flight"
