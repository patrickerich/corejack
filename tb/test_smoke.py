import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


UART_BASE = 0x1000_0000
DEBUG_BASE = 0xFFFF_0000


async def apb_write(dut, addr, data):
    dut.apb_psel_i.value = 1
    dut.apb_penable_i.value = 0
    dut.apb_pwrite_i.value = 1
    dut.apb_paddr_i.value = addr
    dut.apb_pwdata_i.value = data
    await RisingEdge(dut.clk_i)
    dut.apb_penable_i.value = 1
    await RisingEdge(dut.clk_i)
    dut.apb_psel_i.value = 0
    dut.apb_penable_i.value = 0
    dut.apb_pwrite_i.value = 0


async def apb_read(dut, addr):
    dut.apb_psel_i.value = 1
    dut.apb_penable_i.value = 0
    dut.apb_pwrite_i.value = 0
    dut.apb_paddr_i.value = addr
    await RisingEdge(dut.clk_i)
    dut.apb_penable_i.value = 1
    await RisingEdge(dut.clk_i)
    data = int(dut.apb_prdata_o.value)
    dut.apb_psel_i.value = 0
    dut.apb_penable_i.value = 0
    return data


@cocotb.test()
async def smoke_apb_access(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())

    dut.rst_ni.value = 0
    dut.apb_psel_i.value = 0
    dut.apb_penable_i.value = 0
    dut.apb_pwrite_i.value = 0
    dut.apb_paddr_i.value = 0
    dut.apb_pwdata_i.value = 0

    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)

    await apb_write(dut, UART_BASE, 0x1234_ABCD)
    assert await apb_read(dut, UART_BASE) == 0x1234_ABCD
    assert await apb_read(dut, DEBUG_BASE) == 0xD6B0_0001
