from cocotb.clock import Clock
from cocotb.triggers import ReadOnly, ReadWrite, RisingEdge
import cocotb


DEBUG_BASE = 0x0000_0000
DM_HALT_ADDR = DEBUG_BASE + 0x800
DM_HALT_ENTRY_INSN = 0x0180_006F
RAM_BASE = 0x8000_0000


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


def _platform(dut):
    return dut.i_soc_top.gen_platform


async def _wait_for_signal(clk, signal, cycles=32):
    for _ in range(cycles):
        await RisingEdge(clk)
        await ReadOnly()
        if int(signal.value):
            return
    raise AssertionError(f"Timed out waiting for {signal._path}")


@cocotb.test()
async def debug_window_fetch_reaches_dm_through_axi_fabric(dut):
    await _reset(dut)
    p = _platform(dut)

    dut.dbg_force_core_req.value = 1
    dut.dbg_force_sba_req.value = 1
    dut.dbg_instr_req.value = 1
    dut.dbg_instr_addr.value = DM_HALT_ADDR
    dut.dbg_data_req.value = 0
    dut.dbg_sba_req.value = 0

    await ReadWrite()
    await ReadOnly()

    assert int(p.instr_gnt.value) == 1, "debug-window instruction fetch was not granted"

    await _wait_for_signal(dut.clk_i, p.dm_device_req, cycles=8)
    assert int(p.dm_device_addr.value) == 0x800, "dm_top slave address mismatch"
    assert int(p.dm_device_we.value) == 0, "instruction fetch must be a debug-memory read"

    await _wait_for_signal(dut.clk_i, p.instr_rvalid, cycles=8)

    assert int(p.instr_rvalid.value) == 1, "debug-memory read did not produce a response"
    assert int(p.instr_rdata.value) == DM_HALT_ENTRY_INSN, (
        f"unexpected halt-entry instruction 0x{int(p.instr_rdata.value):08x}"
    )

    await RisingEdge(dut.clk_i)
    dut.dbg_force_core_req.value = 0
    dut.dbg_force_sba_req.value = 0


@cocotb.test()
async def sba_writes_and_reads_ram_while_core_is_in_ndmreset(dut):
    await _reset(dut)
    p = _platform(dut)

    dut.dbg_force_ndmreset.value = 1
    dut.dbg_force_sba_req.value = 1
    dut.dbg_sba_addr.value = RAM_BASE
    dut.dbg_sba_be.value = 0xF

    for _ in range(8):
        await RisingEdge(dut.clk_i)
    await ReadOnly()
    assert int(p.core_rst_ni.value) == 0, "core reset was not asserted by ndmreset"
    assert int(p.instr_req.value) == 0, "core instruction traffic active during ndmreset"
    assert int(p.data_req.value) == 0, "core data traffic active during ndmreset"

    await RisingEdge(dut.clk_i)
    dut.dbg_sba_we.value = 1
    dut.dbg_sba_wdata.value = 0xA5A5_1234
    dut.dbg_sba_req.value = 1
    await _wait_for_signal(dut.clk_i, p.sba_gnt)
    await RisingEdge(dut.clk_i)
    dut.dbg_sba_req.value = 0
    await _wait_for_signal(dut.clk_i, p.sba_r_valid)
    assert int(p.sba_r_err.value) == 0, "SBA RAM write returned an error"

    await RisingEdge(dut.clk_i)
    dut.dbg_sba_we.value = 0
    dut.dbg_sba_req.value = 1
    await _wait_for_signal(dut.clk_i, p.sba_gnt)
    await RisingEdge(dut.clk_i)
    dut.dbg_sba_req.value = 0
    await _wait_for_signal(dut.clk_i, p.sba_r_valid)
    assert int(p.sba_r_err.value) == 0, "SBA RAM read returned an error"
    assert int(p.sba_r_rdata.value) == 0xA5A5_1234, (
        f"SBA RAM readback mismatch: 0x{int(p.sba_r_rdata.value):08x}"
    )

    await RisingEdge(dut.clk_i)
    dut.dbg_force_sba_req.value = 0
    dut.dbg_force_ndmreset.value = 0
