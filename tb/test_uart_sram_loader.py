import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


BIT_CYCLES = 10
ACK = 0x06


async def wait_cycles(dut, cycles):
    for _ in range(cycles):
        await RisingEdge(dut.clk_i)


async def reset_dut(dut):
    dut.enable_i.value = 0
    dut.uart_rx_i.value = 1
    dut.mem_gnt_i.value = 0
    dut.mem_rvalid_i.value = 0
    dut.mem_err_i.value = 0
    dut.rst_ni.value = 0
    await wait_cycles(dut, 5)
    dut.rst_ni.value = 1
    await wait_cycles(dut, 2)
    dut.enable_i.value = 1
    await wait_cycles(dut, 4)
    assert int(dut.active_o.value) == 1


async def uart_send_byte(dut, value):
    dut.uart_rx_i.value = 0
    await wait_cycles(dut, BIT_CYCLES)
    for bit in range(8):
        dut.uart_rx_i.value = (value >> bit) & 1
        await wait_cycles(dut, BIT_CYCLES)
    dut.uart_rx_i.value = 1
    await wait_cycles(dut, BIT_CYCLES)


async def uart_recv_byte(dut):
    await FallingEdge(dut.uart_tx_o)
    await wait_cycles(dut, BIT_CYCLES + BIT_CYCLES // 2)
    value = 0
    for bit in range(8):
        value |= int(dut.uart_tx_o.value) << bit
        await wait_cycles(dut, BIT_CYCLES)
    assert int(dut.uart_tx_o.value) == 1
    await wait_cycles(dut, BIT_CYCLES)
    return value


async def expect_mem_write(dut, *, addr, byte):
    for _ in range(80):
        await RisingEdge(dut.clk_i)
        if int(dut.mem_req_o.value):
            lane = addr & 0x7
            assert int(dut.mem_we_o.value) == 1
            assert int(dut.mem_addr_o.value) == addr
            assert int(dut.mem_be_o.value) == (1 << lane)
            assert ((int(dut.mem_wdata_o.value) >> (8 * lane)) & 0xFF) == byte
            assert int(dut.mem_rready_o.value) == 1
            dut.mem_gnt_i.value = 1
            await RisingEdge(dut.clk_i)
            dut.mem_gnt_i.value = 0
            dut.mem_rvalid_i.value = 1
            await RisingEdge(dut.clk_i)
            dut.mem_rvalid_i.value = 0
            return
    raise AssertionError("loader memory write request did not arrive")


@cocotb.test()
async def ping_write_and_release_over_uart(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await uart_send_byte(dut, ord("?"))
    assert await uart_recv_byte(dut) == ACK

    await uart_send_byte(dut, ord("W"))
    for byte in [0x03, 0x00, 0x00, 0x80, 0x02, 0x00]:
        await uart_send_byte(dut, byte)

    await uart_send_byte(dut, 0xA5)
    await expect_mem_write(dut, addr=0x8000_0003, byte=0xA5)
    await uart_send_byte(dut, 0x5A)
    await expect_mem_write(dut, addr=0x8000_0004, byte=0x5A)
    assert await uart_recv_byte(dut) == ACK

    assert int(dut.active_o.value) == 1
    await uart_send_byte(dut, ord("G"))
    assert await uart_recv_byte(dut) == ACK
    await wait_cycles(dut, 4)
    assert int(dut.active_o.value) == 0
    assert int(dut.done_o.value) == 1
