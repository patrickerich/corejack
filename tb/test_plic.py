"""cocotb regression for soc_plic.

Covers the RISC-V PLIC behaviors the platform relies on: priority/enable/
threshold gating of the EIP output, claim/complete with the level-triggered
gateway rule (no re-pend while claimed, re-pend after completion if the source
is still asserted), priority ordering with lowest-ID tie-break, completion of
a disabled source being ignored, and the standard register layout.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


def prio_addr(src: int) -> int:
    return 4 * src


PENDING = 0x1000
ENABLE = 0x2000
THRESHOLD = 0x200000
CLAIM = 0x200004


async def settle(dut) -> None:
    await Timer(1, units="ns")


async def reset_dut(dut) -> None:
    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    dut.reg_valid_i.value = 0
    dut.reg_write_i.value = 0
    dut.reg_addr_i.value = 0
    dut.reg_wdata_i.value = 0
    dut.reg_wstrb_i.value = 0
    dut.irq_sources_i.value = 0
    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def reg_write(dut, addr: int, data: int, strb: int = 0xF) -> None:
    dut.reg_valid_i.value = 1
    dut.reg_write_i.value = 1
    dut.reg_addr_i.value = addr
    dut.reg_wdata_i.value = data
    dut.reg_wstrb_i.value = strb
    await RisingEdge(dut.clk_i)
    dut.reg_valid_i.value = 0
    dut.reg_write_i.value = 0
    await settle(dut)


async def reg_read(dut, addr: int) -> int:
    dut.reg_valid_i.value = 1
    dut.reg_write_i.value = 0
    dut.reg_addr_i.value = addr
    await settle(dut)
    assert int(dut.reg_ready_o.value) == 1
    assert int(dut.reg_error_o.value) == 0
    data = int(dut.reg_rdata_o.value)
    await RisingEdge(dut.clk_i)
    dut.reg_valid_i.value = 0
    await settle(dut)
    return data


async def wait_cycles(dut, cycles: int) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.clk_i)
    await settle(dut)


def irq(dut) -> int:
    return int(dut.irq_o.value)


@cocotb.test()
async def test_gating_priority_enable_threshold(dut):
    """EIP requires pending + enabled + nonzero priority above the threshold."""
    await reset_dut(dut)

    assert await reg_read(dut, CLAIM) == 0
    assert await reg_read(dut, PENDING) == 0
    assert irq(dut) == 0

    # Source ID 1 pends (latched) but is neither enabled nor prioritized.
    dut.irq_sources_i.value = 0x1
    await wait_cycles(dut, 2)
    assert await reg_read(dut, PENDING) == 0x2
    assert irq(dut) == 0

    # A pending level source stays latched even if it deasserts.
    dut.irq_sources_i.value = 0x0
    await wait_cycles(dut, 2)
    assert await reg_read(dut, PENDING) == 0x2

    await reg_write(dut, ENABLE, 0x2)
    assert irq(dut) == 0  # priority still 0

    await reg_write(dut, prio_addr(1), 1)
    assert await reg_read(dut, prio_addr(1)) == 1
    assert irq(dut) == 1

    # Threshold gates EIP: priority must be strictly greater.
    await reg_write(dut, THRESHOLD, 1)
    assert irq(dut) == 0
    # ... but claim ignores the threshold (spec), so the source is claimable.
    assert await reg_read(dut, CLAIM) == 1
    await reg_write(dut, CLAIM, 1)
    await reg_write(dut, THRESHOLD, 0)


@cocotb.test()
async def test_claim_complete_gateway(dut):
    """Claim clears pending and blocks re-pend until completion."""
    await reset_dut(dut)

    await reg_write(dut, ENABLE, 0x2)
    await reg_write(dut, prio_addr(1), 1)
    dut.irq_sources_i.value = 0x1
    await wait_cycles(dut, 2)
    assert irq(dut) == 1

    assert await reg_read(dut, CLAIM) == 1
    assert await reg_read(dut, PENDING) == 0
    assert irq(dut) == 0

    # Still asserted, but claimed-not-completed: must not pend again.
    await wait_cycles(dut, 4)
    assert await reg_read(dut, PENDING) == 0
    assert await reg_read(dut, CLAIM) == 0

    # Completion re-opens the gateway; the still-asserted level pends again.
    await reg_write(dut, CLAIM, 1)
    await wait_cycles(dut, 2)
    assert await reg_read(dut, PENDING) == 0x2
    assert irq(dut) == 1

    # Claim, drop the source, complete: nothing pends.
    assert await reg_read(dut, CLAIM) == 1
    dut.irq_sources_i.value = 0x0
    await reg_write(dut, CLAIM, 1)
    await wait_cycles(dut, 4)
    assert await reg_read(dut, PENDING) == 0
    assert irq(dut) == 0


@cocotb.test()
async def test_priority_order_and_tie_break(dut):
    """Highest priority wins a claim; equal priorities go to the lowest ID."""
    await reset_dut(dut)

    await reg_write(dut, ENABLE, 0xC)  # IDs 2 and 3
    await reg_write(dut, prio_addr(2), 1)
    await reg_write(dut, prio_addr(3), 2)
    dut.irq_sources_i.value = 0x6  # sources for IDs 2 and 3
    await wait_cycles(dut, 2)
    assert await reg_read(dut, PENDING) == 0xC

    assert await reg_read(dut, CLAIM) == 3
    assert await reg_read(dut, CLAIM) == 2
    dut.irq_sources_i.value = 0x0
    await reg_write(dut, CLAIM, 3)
    await reg_write(dut, CLAIM, 2)

    # Equal priorities: lowest ID first.
    await reg_write(dut, prio_addr(2), 2)
    dut.irq_sources_i.value = 0x6
    await wait_cycles(dut, 2)
    assert await reg_read(dut, CLAIM) == 2
    assert await reg_read(dut, CLAIM) == 3


@cocotb.test()
async def test_complete_disabled_source_ignored(dut):
    """Completion of a source whose enable bit is clear is silently ignored."""
    await reset_dut(dut)

    await reg_write(dut, ENABLE, 0x2)
    await reg_write(dut, prio_addr(1), 1)
    dut.irq_sources_i.value = 0x1
    await wait_cycles(dut, 2)
    assert await reg_read(dut, CLAIM) == 1

    # Disabled completion is ignored: the gateway stays closed.
    await reg_write(dut, ENABLE, 0x0)
    await reg_write(dut, CLAIM, 1)
    await wait_cycles(dut, 4)
    assert await reg_read(dut, PENDING) == 0

    # Re-enabled completion reopens it.
    await reg_write(dut, ENABLE, 0x2)
    await reg_write(dut, CLAIM, 1)
    await wait_cycles(dut, 2)
    assert await reg_read(dut, PENDING) == 0x2
    assert await reg_read(dut, CLAIM) == 1
    dut.irq_sources_i.value = 0x0
    await reg_write(dut, CLAIM, 1)


@cocotb.test()
async def test_register_layout_corners(dut):
    """Source 0 is reserved, undecoded offsets read zero, wstrb=0 is ignored."""
    await reset_dut(dut)

    # Source 0 priority is reserved: writes ignored, reads zero.
    await reg_write(dut, prio_addr(0), 7)
    assert await reg_read(dut, prio_addr(0)) == 0

    # Enable readback.
    await reg_write(dut, ENABLE, 0x1E)
    assert await reg_read(dut, ENABLE) == 0x1E

    # Undecoded offsets.
    assert await reg_read(dut, 0x3000) == 0
    assert await reg_read(dut, 0x300000) == 0
    await reg_write(dut, 0x3000, 0xFFFFFFFF)

    # A write with no strobes set must not take effect.
    await reg_write(dut, THRESHOLD, 5, strb=0x0)
    assert await reg_read(dut, THRESHOLD) == 0
    await reg_write(dut, THRESHOLD, 5)
    assert await reg_read(dut, THRESHOLD) == 5
