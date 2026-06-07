import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


async def reset_dut(dut):
    dut.obi_req_i.value = 0
    dut.obi_we_i.value = 0
    dut.obi_addr_i.value = 0
    dut.obi_wdata_i.value = 0
    dut.obi_be_i.value = 0
    dut.obi_rready_i.value = 1
    dut.obi1_req_i.value = 0
    dut.obi1_we_i.value = 0
    dut.obi1_addr_i.value = 0
    dut.obi1_wdata_i.value = 0
    dut.obi1_be_i.value = 0
    dut.obi1_rready_i.value = 1
    dut.mem_gnt_i.value = 0
    dut.mem_rvalid_i.value = 0
    dut.mem_rdata_i.value = 0
    dut.mem_err_i.value = 0
    dut.apb_pready_i.value = 0
    dut.apb_prdata_i.value = 0
    dut.apb_pslverr_i.value = 0
    dut.dm_rdata_i.value = 0
    dut.rst_ni.value = 0
    for _ in range(5):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1
    for _ in range(2):
        await RisingEdge(dut.clk_i)


async def issue_obi(dut, *, we, addr, wdata=0, be=0xF):
    dut.obi_we_i.value = int(we)
    dut.obi_addr_i.value = addr
    dut.obi_wdata_i.value = wdata
    dut.obi_be_i.value = be
    dut.obi_req_i.value = 1
    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.obi_gnt_o.value:
            dut.obi_req_i.value = 0
            return
    raise AssertionError("OBI request was not granted")


async def issue_obi1(dut, *, we, addr, wdata=0, be=0xF):
    dut.obi1_we_i.value = int(we)
    dut.obi1_addr_i.value = addr
    dut.obi1_wdata_i.value = wdata
    dut.obi1_be_i.value = be
    dut.obi1_req_i.value = 1
    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.obi1_gnt_o.value:
            dut.obi1_req_i.value = 0
            return
    raise AssertionError("OBI1 request was not granted")


async def wait_mem_req(dut, *, we, addr):
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if dut.mem_req_o.value:
            assert int(dut.mem_we_o.value) == int(we)
            assert int(dut.mem_addr_o.value) == addr
            return
    raise AssertionError("memory request did not arrive")


async def wait_obi_rsp(dut):
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if dut.obi_rvalid_o.value:
            return int(dut.obi_rdata_o.value), int(dut.obi_err_o.value)
    raise AssertionError("OBI response did not arrive")


async def wait_obi1_rsp(dut):
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if dut.obi1_rvalid_o.value:
            return int(dut.obi1_rdata_o.value), int(dut.obi1_err_o.value)
    raise AssertionError("OBI1 response did not arrive")


async def wait_apb_access(dut, *, pwrite, paddr):
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if dut.apb_psel_o.value and dut.apb_penable_o.value:
            assert int(dut.apb_pwrite_o.value) == int(pwrite)
            assert int(dut.apb_paddr_o.value) == paddr
            return
    raise AssertionError("APB access did not arrive")


async def wait_dm_req(dut, *, we, addr):
    for _ in range(40):
        await RisingEdge(dut.clk_i)
        if dut.dm_req_o.value:
            assert int(dut.dm_we_o.value) == int(we)
            assert int(dut.dm_addr_o.value) == addr
            return
    raise AssertionError("debug-memory request did not arrive")


@cocotb.test()
async def read_low_and_high_lanes(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x8000_0000)
    await wait_mem_req(dut, we=False, addr=0x8000_0000)
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0x11223344_AABBCCDD
    data, err = await wait_obi_rsp(dut)
    assert err == 0
    assert data == 0xAABBCCDD
    dut.mem_gnt_i.value = 0
    dut.mem_rvalid_i.value = 0

    await issue_obi(dut, we=False, addr=0x8000_0004)
    await wait_mem_req(dut, we=False, addr=0x8000_0004)
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0x11223344_AABBCCDD
    data, err = await wait_obi_rsp(dut)
    assert err == 0
    assert data == 0x11223344


@cocotb.test()
async def write_uses_selected_axi_lane(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=True, addr=0x8000_0004, wdata=0x55667788, be=0x5)
    await wait_mem_req(dut, we=True, addr=0x8000_0004)
    assert int(dut.mem_wdata_o.value) == 0x55667788_00000000
    assert int(dut.mem_be_o.value) == 0x50

    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert data == 0
    assert err == 0


@cocotb.test()
async def narrow_writes_preserve_byte_lanes_on_64bit_axi(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=True, addr=0x8000_0001, wdata=0xAABBCCDD, be=0x2)
    await wait_mem_req(dut, we=True, addr=0x8000_0001)
    assert int(dut.mem_wdata_o.value) == 0x00000000_AABBCCDD
    assert int(dut.mem_be_o.value) == 0x02
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert data == 0
    assert err == 0
    dut.mem_gnt_i.value = 0
    dut.mem_rvalid_i.value = 0

    await issue_obi(dut, we=True, addr=0x8000_0006, wdata=0x11223344, be=0xC)
    await wait_mem_req(dut, we=True, addr=0x8000_0006)
    assert int(dut.mem_wdata_o.value) == 0x11223344_00000000
    assert int(dut.mem_be_o.value) == 0xC0
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert data == 0
    assert err == 0


@cocotb.test()
async def read_lane_selection_uses_request_address_until_response(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x8000_0004)
    await wait_mem_req(dut, we=False, addr=0x8000_0004)
    dut.mem_gnt_i.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk_i)
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0x55667788_11223344
    data, err = await wait_obi_rsp(dut)
    assert err == 0
    assert data == 0x55667788


@cocotb.test()
async def response_backpressure_holds_until_ready(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x8000_0000)
    await wait_mem_req(dut, we=False, addr=0x8000_0000)
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0xFEEDC0DE_12345678
    dut.obi_rready_i.value = 0

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.obi_rvalid_o.value:
            break
    assert int(dut.obi_rvalid_o.value) == 1

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        assert int(dut.obi_rvalid_o.value) == 1
        assert int(dut.obi_rdata_o.value) == 0x12345678

    dut.obi_rready_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert data == 0x12345678
    assert err == 0


@cocotb.test()
async def error_response_propagates(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x8000_0000)
    await wait_mem_req(dut, we=False, addr=0x8000_0000)
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0
    dut.mem_err_i.value = 1
    _, err = await wait_obi_rsp(dut)
    assert err == 1


@cocotb.test()
async def second_obi_port_reaches_shared_memory_target(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi1(dut, we=False, addr=0x8000_0004)
    await wait_mem_req(dut, we=False, addr=0x8000_0004)
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0xCAFEBABE_01020304
    data, err = await wait_obi1_rsp(dut)
    assert err == 0
    assert data == 0xCAFEBABE


@cocotb.test()
async def invalid_axi_address_returns_decode_error(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x2000_0000)
    _data, err = await wait_obi_rsp(dut)
    # The crossbar's error slave answers a decode miss with RESP_DECERR; the
    # read data is implementation-defined poison (axi_err_slv default), so only
    # the error flag is checked here.
    assert err == 1
    assert int(dut.mem_req_o.value) == 0
    assert int(dut.apb_psel_o.value) == 0
    assert int(dut.dm_req_o.value) == 0


@cocotb.test()
async def decode_error_response_obeys_backpressure(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    dut.obi_rready_i.value = 0
    await issue_obi(dut, we=False, addr=0x2000_0000)

    for _ in range(20):
        await RisingEdge(dut.clk_i)
        if dut.obi_rvalid_o.value:
            break
    assert int(dut.obi_rvalid_o.value) == 1

    for _ in range(5):
        await RisingEdge(dut.clk_i)
        assert int(dut.obi_rvalid_o.value) == 1
        assert int(dut.obi_err_o.value) == 1

    dut.obi_rready_i.value = 1
    _data, err = await wait_obi_rsp(dut)
    assert err == 1


@cocotb.test()
async def uart_write_routes_through_axi_to_apb_bridge(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=True, addr=0x1000_0004, wdata=0x55667788, be=0xA)
    await wait_apb_access(dut, pwrite=True, paddr=0x4)
    assert int(dut.apb_pwdata_o.value) == 0x55667788
    assert int(dut.apb_pstrb_o.value) == 0xA
    dut.apb_pready_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert data == 0
    assert err == 0


@cocotb.test()
async def uart_read_routes_through_axi_to_apb_bridge(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x1000_0004)
    await wait_apb_access(dut, pwrite=False, paddr=0x4)
    dut.apb_prdata_i.value = 0x13579BDF
    dut.apb_pready_i.value = 1
    data, err = await wait_obi_rsp(dut)
    assert err == 0
    assert data == 0x13579BDF


@cocotb.test()
async def debug_read_routes_through_axi_to_dm_bridge(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=False, addr=0x0000_0804)
    await wait_dm_req(dut, we=False, addr=0x804)
    dut.dm_rdata_i.value = 0x0180006F_00000000
    data, err = await wait_obi_rsp(dut)
    assert err == 0
    assert data == 0x0180006F


@cocotb.test()
async def debug_write_routes_through_axi_to_dm_bridge(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    await issue_obi(dut, we=True, addr=0x0000_0004, wdata=0xDEADBEEF, be=0x3)
    await wait_dm_req(dut, we=True, addr=0x4)
    assert int(dut.dm_be_o.value) == 0x30
    assert int(dut.dm_wdata_o.value) == 0xDEADBEEF_00000000
    data, err = await wait_obi_rsp(dut)
    assert data == 0
    assert err == 0


@cocotb.test()
async def concurrent_initiators_reach_distinct_targets(dut):
    """Two initiators targeting different fabric targets must progress
    concurrently. This is the property the crossbar buys over the former
    single-outstanding arbiter: with that arbiter a transaction stalled at one
    target blocked the whole fabric, so the second initiator could never reach
    its target and this test would deadlock."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    # Initiator 0 reads RAM, but the memory side is never granted: the read
    # stays outstanding at the RAM target (mem_req_o asserted, no grant).
    dut.mem_gnt_i.value = 0
    await issue_obi(dut, we=False, addr=0x8000_0000)
    await wait_mem_req(dut, we=False, addr=0x8000_0000)
    assert int(dut.mem_req_o.value) == 1

    # While that RAM read is still in flight, initiator 1 targets the debug
    # module. With per-target arbitration it reaches and completes independently.
    await issue_obi1(dut, we=False, addr=0x0000_0804)
    await wait_dm_req(dut, we=False, addr=0x804)
    dut.dm_rdata_i.value = 0x0180006F_00000000
    data1, err1 = await wait_obi1_rsp(dut)
    assert err1 == 0
    assert data1 == 0x0180006F

    # The RAM read is still parked; release it now and confirm it completes.
    assert int(dut.mem_req_o.value) == 1
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0x11223344_AABBCCDD
    data0, err0 = await wait_obi_rsp(dut)
    assert err0 == 0
    assert data0 == 0xAABBCCDD


@cocotb.test()
async def both_initiators_share_one_target(dut):
    """Both initiators read the same target. The single-outstanding memory
    adapter serializes them, but the crossbar must round-robin between the two
    slave ports and route each response back to the correct initiator by ID."""
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    await reset_dut(dut)

    # Free-running memory: grant and return the same word for every request.
    dut.mem_gnt_i.value = 1
    dut.mem_rvalid_i.value = 1
    dut.mem_rdata_i.value = 0x11223344_AABBCCDD

    rsp0 = cocotb.start_soon(wait_obi_rsp(dut))
    rsp1 = cocotb.start_soon(wait_obi1_rsp(dut))

    await issue_obi(dut, we=False, addr=0x8000_0000)
    await issue_obi1(dut, we=False, addr=0x8000_0000)

    data0, err0 = await rsp0
    data1, err1 = await rsp1
    assert err0 == 0 and err1 == 0
    assert data0 == 0xAABBCCDD
    assert data1 == 0xAABBCCDD
