import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge


def _get_env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value, 0)


def _safe_int(handle, default=None):
    try:
        return int(handle.value)
    except Exception:
        return default


def _safe_handle(root, path: str):
    handle = root
    try:
        for name in path.split("."):
            handle = getattr(handle, name)
    except AttributeError:
        return None
    return handle


def _write_touches_range(addr: int, be: int, data_bytes: int, watch_lo: int, watch_hi: int) -> bool:
    for byte_idx in range(data_bytes):
        if ((be >> byte_idx) & 1) == 0:
            continue
        byte_addr = addr + byte_idx
        if watch_lo <= byte_addr < watch_hi:
            return True
    return False


@cocotb.test()
async def run_soc_software(dut):
    timeout_cycles = _get_env_int("COREJACK_TIMEOUT_CYCLES", 1000000)
    trace_bus = bool(_get_env_int("COREJACK_TRACE_BUS", 0))
    trace_uart = bool(_get_env_int("COREJACK_TRACE_UART", 0))
    trace_cv32e40x_if = bool(_get_env_int("COREJACK_TRACE_CV32E40X_IF", 0))
    check_cv32e40x_if = bool(_get_env_int("COREJACK_CHECK_CV32E40X_IF_CONTRACT", 0))
    trace_after_cycle = _get_env_int("COREJACK_TRACE_AFTER_CYCLE", 0)
    trace_after_uart = os.getenv("COREJACK_TRACE_AFTER_UART", "")
    trace_on_cv32e40x_mcause = bool(_get_env_int("COREJACK_TRACE_ON_CV32E40X_MCAUSE", 0))
    force_debug_cycle = _get_env_int("COREJACK_FORCE_DEBUG_REQ_CYCLE", -1)
    force_debug_cycles = _get_env_int("COREJACK_FORCE_DEBUG_REQ_CYCLES", 200)
    force_debug_done_cycles = _get_env_int("COREJACK_FORCE_DEBUG_DONE_CYCLES", 400)
    trace_limit = _get_env_int("COREJACK_TRACE_LIMIT", 80)
    watch_write_addr = _get_env_int("COREJACK_WATCH_WRITE_ADDR", -1)
    watch_write_size = _get_env_int("COREJACK_WATCH_WRITE_SIZE", 4)
    watch_write_after_cycle = _get_env_int("COREJACK_WATCH_WRITE_AFTER_CYCLE", 0)
    watch_read_addr = _get_env_int("COREJACK_WATCH_READ_ADDR", -1)
    watch_read_size = _get_env_int("COREJACK_WATCH_READ_SIZE", 4)
    watch_pc_addr = _get_env_int("COREJACK_WATCH_PC_ADDR", -1)
    watch_pc_size = _get_env_int("COREJACK_WATCH_PC_SIZE", 4)
    pc_history_depth = _get_env_int("COREJACK_PC_HISTORY_DEPTH", 64)
    expect_uart = os.getenv("COREJACK_EXPECT_UART", "")

    cocotb.start_soon(Clock(dut.clk_i, 20, unit="ns").start())

    dut.rst_ni.value = 0
    for _ in range(10):
        await RisingEdge(dut.clk_i)
    dut.rst_ni.value = 1

    captured = []
    line_buffer = []
    trace_count = 0
    trace_armed = (
        trace_after_cycle <= 0
        and not trace_after_uart
        and not trace_on_cv32e40x_mcause
    )
    trace_after_uart_seen = False
    platform = _safe_handle(dut, "i_soc_top.gen_platform")
    uart_apb_req = _safe_handle(dut, "i_soc_top.gen_platform.uart_apb_req")
    mem_req_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_req")
    mem_we_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_we")
    mem_gnt_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_gnt")
    mem_addr_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_addr")
    mem_be_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_be")
    mem_wdata_h = _safe_handle(dut, "i_soc_top.gen_platform.mem_init_wdata")
    ibex_core_h = _safe_handle(
        dut,
        (
            "i_soc_top.gen_platform.gen_rv32_core_path.i_core_region.gen_ibex."
            "i_ibex_adapter.i_ibex.u_ibex_top.u_ibex_core"
        ),
    )
    cv32e40x_adapter = _safe_handle(
        dut,
        "i_soc_top.gen_platform.gen_rv32_core_path.i_core_region.gen_cv32e40x.i_cv32e40x_adapter",
    )
    cv32e40x_csrs = _safe_handle(
        dut,
        (
            "i_soc_top.gen_platform.gen_rv32_core_path.i_core_region.gen_cv32e40x."
            "i_cv32e40x_adapter.i_cv32e40x.cs_registers_i"
        ),
    )
    cv32e40x_if = _safe_handle(
        dut,
        (
            "i_soc_top.gen_platform.gen_rv32_core_path.i_core_region.gen_cv32e40x."
            "i_cv32e40x_adapter.i_cv32e40x.if_stage_i"
        ),
    )
    cv32e40x_prefetcher = _safe_handle(
        dut,
        (
            "i_soc_top.gen_platform.gen_rv32_core_path.i_core_region.gen_cv32e40x."
            "i_cv32e40x_adapter.i_cv32e40x.if_stage_i.prefetch_unit_i.prefetcher_i"
        ),
    )
    debug_req_hook = getattr(dut, "dbg_force_debug_req", None)
    if debug_req_hook is not None:
        debug_req_hook.value = 0
    cva6_debug_mode_h = _safe_handle(dut, "dbg_cva6_debug_mode")
    cva6_set_debug_pc_h = _safe_handle(dut, "dbg_cva6_set_debug_pc")
    cva6_halt_frontend_h = _safe_handle(dut, "dbg_cva6_halt_frontend")
    cva6_frontend_req_h = _safe_handle(dut, "dbg_cva6_frontend_req")
    cva6_frontend_ready_h = _safe_handle(dut, "dbg_cva6_frontend_ready")
    cva6_frontend_valid_h = _safe_handle(dut, "dbg_cva6_frontend_valid")
    cva6_frontend_npc_h = _safe_handle(dut, "dbg_cva6_frontend_npc")
    cva6_frontend_vaddr_h = _safe_handle(dut, "dbg_cva6_frontend_vaddr")
    cva6_frontend_data_h = _safe_handle(dut, "dbg_cva6_frontend_data")
    cva6_axi_aw_valid_h = _safe_handle(dut, "dbg_cva6_axi_aw_valid")
    cva6_axi_aw_ready_h = _safe_handle(dut, "dbg_cva6_axi_aw_ready")
    cva6_axi_w_valid_h = _safe_handle(dut, "dbg_cva6_axi_w_valid")
    cva6_axi_w_ready_h = _safe_handle(dut, "dbg_cva6_axi_w_ready")
    cva6_axi_ar_valid_h = _safe_handle(dut, "dbg_cva6_axi_ar_valid")
    cva6_axi_ar_ready_h = _safe_handle(dut, "dbg_cva6_axi_ar_ready")
    cva6_axi_aw_addr_h = _safe_handle(dut, "dbg_cva6_axi_aw_addr")
    cva6_axi_ar_addr_h = _safe_handle(dut, "dbg_cva6_axi_ar_addr")
    cva6_debug_visible = cva6_debug_mode_h is not None
    instr_buffer = _safe_handle(dut, "i_soc_top.gen_platform.gen_rv32_core_path.i_instr_buffer")
    cv32e40x_raw_fetch_words = set()
    forced_debug_released = False
    debug_halted_write_seen = False
    cva6_debug_aw_halted_seen = False
    cva6_debug_w_seen = False
    cva6_debug_aw_halted_addr = 0
    recent_data_writes = []
    recent_mem_writes = []
    recent_data_reads = []
    recent_pcs = []
    last_pc_wb = None
    pending_data_responses = []
    last_cv32e40x_mcause = 0

    for cycle in range(timeout_cycles):
        if cycle >= trace_after_cycle and not trace_after_uart and not trace_on_cv32e40x_mcause:
            trace_armed = True

        if trace_armed and (trace_bus or trace_uart or trace_cv32e40x_if or check_cv32e40x_if) and trace_count < trace_limit:
            await FallingEdge(dut.clk_i)
        await RisingEdge(dut.clk_i)

        if debug_req_hook is not None and force_debug_cycle >= 0:
            if cycle == force_debug_cycle:
                debug_req_hook.value = 1
                dut._log.info("debug-diag: forced soc_top debug_req_o high at cycle=%d", cycle)
            if cycle == force_debug_cycle + force_debug_cycles:
                debug_req_hook.value = 0
                forced_debug_released = True
                dut._log.info("debug-diag: released soc_top debug_req_o at cycle=%d", cycle)

        if cv32e40x_adapter is not None and (trace_cv32e40x_if or check_cv32e40x_if):
            raw_req = _safe_int(getattr(cv32e40x_adapter, "instr_req_o", None), 0)
            raw_gnt = _safe_int(getattr(cv32e40x_adapter, "instr_gnt_i", None), 0)
            raw_addr = _safe_int(getattr(cv32e40x_adapter, "raw_instr_addr", None))

            if raw_req and raw_gnt and raw_addr is not None:
                raw_word = raw_addr & ~0x3
                cv32e40x_raw_fetch_words.add(raw_word)
                if trace_armed and trace_cv32e40x_if and trace_count < trace_limit:
                    dut._log.info(
                        "cv32e40x-if accept cycle=%d raw_addr=0x%08x adapted_addr=0x%08x",
                        cycle,
                        raw_word,
                        _safe_int(getattr(cv32e40x_adapter, "instr_addr_o", None), 0) & ~0x3,
                    )
                    trace_count += 1

            if cv32e40x_if is not None:
                prefetch_valid = _safe_int(getattr(cv32e40x_if, "prefetch_valid", None), 0)
                prefetch_ready = _safe_int(getattr(cv32e40x_if, "prefetch_ready", None), 0)
                pc_if = _safe_int(getattr(cv32e40x_if, "pc_if_o", None))
                if prefetch_valid and prefetch_ready and pc_if is not None:
                    pc_word = pc_if & ~0x3
                    if trace_armed and trace_cv32e40x_if and trace_count < trace_limit:
                        dut._log.info(
                            "cv32e40x-if deliver cycle=%d pc_if=0x%08x pc_word=0x%08x raw_requested=%s",
                            cycle,
                            pc_if,
                            pc_word,
                            "yes" if pc_word in cv32e40x_raw_fetch_words else "no",
                        )
                        trace_count += 1
                    if check_cv32e40x_if and pc_word not in cv32e40x_raw_fetch_words:
                        raise AssertionError(
                            "CV32E40X IF contract mismatch: delivered instruction PC "
                            f"0x{pc_if:08x}, but raw core boundary never accepted a fetch "
                            f"for word address 0x{pc_word:08x}. Accepted raw fetch words: "
                            f"{', '.join(f'0x{addr:08x}' for addr in sorted(cv32e40x_raw_fetch_words))}"
                        )

        if ibex_core_h is not None:
            pc_wb = _safe_int(getattr(ibex_core_h, "pc_wb", None))
            pc_id = _safe_int(getattr(ibex_core_h, "pc_id", None))
            if pc_wb is not None and pc_wb != last_pc_wb:
                recent_pcs.append((cycle, pc_id if pc_id is not None else 0, pc_wb))
                recent_pcs = recent_pcs[-pc_history_depth:]
                last_pc_wb = pc_wb
                if watch_pc_addr >= 0:
                    watch_lo = watch_pc_addr
                    watch_hi = watch_pc_addr + watch_pc_size
                    if watch_lo <= pc_wb < watch_hi:
                        pc_history = ", ".join(
                            f"{c}:id=0x{pid:08x}/wb=0x{pwb:08x}" for c, pid, pwb in recent_pcs
                        )
                        dut._log.warning(
                            "Watched PC reached: cycle=%d pc_id=0x%08x pc_wb=0x%08x recent_pcs=[%s]",
                            cycle,
                            pc_id if pc_id is not None else 0,
                            pc_wb,
                            pc_history,
                        )

        if cv32e40x_csrs is not None and trace_on_cv32e40x_mcause:
            mcause_now = _safe_int(getattr(cv32e40x_csrs, "mcause_rdata", None), 0)
            if mcause_now != last_cv32e40x_mcause:
                dut._log.info(
                    "cv32e40x-trace trigger: mcause changed cycle=%d old=0x%08x new=0x%08x",
                    cycle,
                    last_cv32e40x_mcause,
                    mcause_now,
                )
                trace_armed = True
                last_cv32e40x_mcause = mcause_now

        if trace_armed and trace_bus and trace_count < trace_limit and platform is not None:
            instr_req = _safe_int(platform.instr_req, 0)
            instr_gnt = _safe_int(platform.instr_gnt, 0)
            instr_rvalid = _safe_int(platform.instr_rvalid, 0)
            data_req = _safe_int(platform.data_req, 0)
            data_gnt = _safe_int(platform.data_gnt, 0)
            data_rvalid = _safe_int(platform.data_rvalid, 0)
            if (
                instr_req
                or instr_gnt
                or instr_rvalid
                or data_req
                or data_gnt
                or data_rvalid
                or cv32e40x_adapter is not None
                or cva6_debug_visible
            ):
                msg = (
                    f"trace cycle={cycle} "
                    f"ireq/gnt/rvalid={instr_req}/{instr_gnt}/{instr_rvalid} "
                    f"iaddr=0x{_safe_int(platform.instr_addr, 0):08x} "
                    f"irdata=0x{_safe_int(platform.instr_rdata, 0):08x} "
                    f"dreq/gnt/rvalid={data_req}/{data_gnt}/{data_rvalid} "
                    f"dwe={_safe_int(platform.data_we, 0)} "
                    f"dbe=0x{_safe_int(platform.data_be, 0):x} "
                    f"daddr=0x{_safe_int(platform.data_addr, 0):08x} "
                    f"dwdata=0x{_safe_int(platform.data_wdata, 0):08x} "
                    f"drdata=0x{_safe_int(platform.data_rdata, 0):08x}"
                )
                if cv32e40x_adapter is not None:
                    debug_req = _safe_int(getattr(cv32e40x_adapter, "debug_req_i", None))
                    debug_havereset = _safe_int(cv32e40x_adapter.debug_havereset_unused)
                    debug_running = _safe_int(cv32e40x_adapter.debug_running_unused)
                    debug_halted = _safe_int(cv32e40x_adapter.debug_halted_unused)
                    debug_pc_valid = _safe_int(cv32e40x_adapter.debug_pc_valid_unused)
                    debug_pc = _safe_int(cv32e40x_adapter.debug_pc_unused)
                    core_sleep = _safe_int(cv32e40x_adapter.core_sleep_o)
                    if debug_req is not None:
                        msg += f" debug_req={debug_req}"
                    if debug_havereset is not None and debug_running is not None and debug_halted is not None:
                        msg += f" dbg_state=hr{debug_havereset}/run{debug_running}/halt{debug_halted}"
                    if debug_pc_valid is not None and debug_pc is not None:
                        msg += f" dbg_pc_valid={debug_pc_valid} dbg_pc=0x{debug_pc:08x}"
                    if core_sleep is not None:
                        msg += f" core_sleep={core_sleep}"
                    raw_instr_addr = _safe_int(getattr(cv32e40x_adapter, "raw_instr_addr", None))
                    if raw_instr_addr is not None:
                        msg += f" raw_iaddr=0x{raw_instr_addr:08x}"
                if cv32e40x_if is not None:
                    pc_if = _safe_int(getattr(cv32e40x_if, "pc_if_o", None))
                    prefetch_trans_valid = _safe_int(getattr(cv32e40x_if, "prefetch_trans_valid", None))
                    prefetch_trans_ready = _safe_int(getattr(cv32e40x_if, "prefetch_trans_ready", None))
                    prefetch_trans_addr = _safe_int(getattr(cv32e40x_if, "prefetch_trans_addr", None))
                    bus_trans_valid = _safe_int(getattr(cv32e40x_if, "bus_trans_valid", None))
                    bus_trans_ready = _safe_int(getattr(cv32e40x_if, "bus_trans_ready", None))
                    if pc_if is not None:
                        msg += f" pc_if=0x{pc_if:08x}"
                    if prefetch_trans_valid is not None and prefetch_trans_ready is not None:
                        msg += (
                            f" pf={prefetch_trans_valid}/{prefetch_trans_ready}"
                            f"/0x{prefetch_trans_addr:08x}"
                        )
                    if bus_trans_valid is not None and bus_trans_ready is not None:
                        msg += f" bus={bus_trans_valid}/{bus_trans_ready}"
                if cv32e40x_prefetcher is not None:
                    fetch_branch = _safe_int(getattr(cv32e40x_prefetcher, "fetch_branch_i", None))
                    fetch_branch_addr = _safe_int(getattr(cv32e40x_prefetcher, "fetch_branch_addr_i", None))
                    trans_addr_q = _safe_int(getattr(cv32e40x_prefetcher, "trans_addr_q", None))
                    if fetch_branch is not None:
                        msg += f" branch={fetch_branch}/0x{fetch_branch_addr:08x}"
                    if trans_addr_q is not None:
                        msg += f" trans_q=0x{trans_addr_q:08x}"
                if hasattr(platform, "core_instr_req"):
                    msg += (
                        f" core_i={_safe_int(platform.core_instr_req, 0)}/"
                        f"{_safe_int(platform.core_instr_gnt, 0)}/"
                        f"{_safe_int(platform.core_instr_rvalid, 0)}"
                        f" core_iaddr=0x{_safe_int(platform.core_instr_addr, 0):08x}"
                        f" core_irdata=0x{_safe_int(platform.core_instr_rdata, 0):08x}"
                    )
                if instr_buffer is not None:
                    pending = _safe_int(getattr(instr_buffer, "pending_q", None))
                    outstanding = _safe_int(getattr(instr_buffer, "outstanding_q", None))
                    if pending is not None and outstanding is not None:
                        msg += f" ibuf_pending={pending} ibuf_outstanding={outstanding}"
                if cva6_debug_visible:
                    debug_mode = _safe_int(cva6_debug_mode_h, 0)
                    set_debug_pc = _safe_int(cva6_set_debug_pc_h, 0)
                    halt_frontend = _safe_int(cva6_halt_frontend_h, 0)
                    frontend_req = _safe_int(cva6_frontend_req_h, 0)
                    frontend_ready = _safe_int(cva6_frontend_ready_h, 0)
                    frontend_valid = _safe_int(cva6_frontend_valid_h, 0)
                    frontend_npc = _safe_int(cva6_frontend_npc_h, 0)
                    frontend_vaddr = _safe_int(cva6_frontend_vaddr_h, 0)
                    frontend_data = _safe_int(cva6_frontend_data_h, 0)
                    aw_valid = _safe_int(cva6_axi_aw_valid_h, 0)
                    aw_ready = _safe_int(cva6_axi_aw_ready_h, 0)
                    w_valid = _safe_int(cva6_axi_w_valid_h, 0)
                    w_ready = _safe_int(cva6_axi_w_ready_h, 0)
                    ar_valid = _safe_int(cva6_axi_ar_valid_h, 0)
                    ar_ready = _safe_int(cva6_axi_ar_ready_h, 0)
                    aw_addr = _safe_int(cva6_axi_aw_addr_h, 0)
                    ar_addr = _safe_int(cva6_axi_ar_addr_h, 0)
                    msg += (
                        f" cva6_debug_mode={debug_mode} cva6_set_debug_pc={set_debug_pc}"
                        f" cva6_fe=req{frontend_req}/rdy{frontend_ready}/vld{frontend_valid}"
                        f"/halt{halt_frontend}/npc0x{frontend_npc:08x}/vaddr0x{frontend_vaddr:08x}"
                        f"/data0x{frontend_data:016x}"
                    )
                    if aw_valid or w_valid or ar_valid:
                        msg += (
                            f" cva6_axi_aw={aw_valid}/{aw_ready}/0x{aw_addr:08x}"
                            f" w={w_valid}/{w_ready}"
                            f" ar={ar_valid}/{ar_ready}/0x{ar_addr:08x}"
                        )
                if cv32e40x_csrs is not None:
                    mepc = _safe_int(getattr(cv32e40x_csrs, "mepc_rdata", None))
                    mcause = _safe_int(getattr(cv32e40x_csrs, "mcause_rdata", None))
                    mtval = _safe_int(getattr(cv32e40x_csrs, "mtval_rdata", None))
                    if mepc is not None and mcause is not None:
                        msg += f" mepc=0x{mepc:08x} mcause=0x{mcause:08x}"
                    if mtval is not None:
                        msg += f" mtval=0x{mtval:08x}"
                dut._log.info(msg)
                trace_count += 1

        if platform is not None:
            if (
                _safe_int(getattr(platform, "core_data_req", None), 0)
                and _safe_int(getattr(platform, "core_data_gnt", None), 0)
            ):
                pending_data_responses.append(
                    (
                        cycle,
                        _safe_int(platform.core_data_addr, 0),
                        _safe_int(getattr(platform, "core_data_we", None), 0),
                        _safe_int(getattr(ibex_core_h, "pc_id", None), 0),
                        _safe_int(getattr(ibex_core_h, "pc_wb", None), 0),
                    )
                )

            if _safe_int(getattr(platform, "core_data_rvalid", None), 0) and pending_data_responses:
                req_cycle, req_addr, req_we, req_pc_id, req_pc_wb = pending_data_responses.pop(0)
                if not req_we:
                    recent_data_reads.append(
                        (
                            req_cycle,
                            cycle,
                            req_addr,
                            _safe_int(platform.core_data_rdata, 0),
                            req_pc_id,
                            req_pc_wb,
                            _safe_int(getattr(ibex_core_h, "pc_id", None), 0),
                            _safe_int(getattr(ibex_core_h, "pc_wb", None), 0),
                        )
                    )
                    recent_data_reads = recent_data_reads[-16:]
                if watch_read_addr >= 0 and not req_we:
                    read_lo = req_addr
                    read_hi = req_addr + 4
                    watch_lo = watch_read_addr
                    watch_hi = watch_read_addr + watch_read_size
                    if read_lo < watch_hi and watch_lo < read_hi:
                        dut._log.warning(
                            "Watched core data read: req_cycle=%d rsp_cycle=%d addr=0x%08x "
                            "rdata=0x%08x req_pc_id=0x%08x req_pc_wb=0x%08x "
                            "rsp_pc_id=0x%08x rsp_pc_wb=0x%08x",
                            req_cycle,
                            cycle,
                            req_addr,
                            _safe_int(platform.core_data_rdata, 0),
                            req_pc_id,
                            req_pc_wb,
                            _safe_int(getattr(ibex_core_h, "pc_id", None), 0),
                            _safe_int(getattr(ibex_core_h, "pc_wb", None), 0),
                        )

            data_req_h = getattr(platform, "data_req", None)
            data_we_h = getattr(platform, "data_we", None)
            data_gnt_h = getattr(platform, "data_gnt", None)
            if _safe_int(data_req_h, 0) and _safe_int(data_we_h, 0) and _safe_int(data_gnt_h, 0):
                if _safe_int(data_we_h, 0):
                    recent_data_writes.append(
                        (
                            cycle,
                            _safe_int(platform.data_addr, 0),
                            _safe_int(platform.data_be, 0),
                            _safe_int(platform.data_wdata, 0),
                            _safe_int(getattr(ibex_core_h, "pc_id", None), 0),
                            _safe_int(getattr(ibex_core_h, "pc_wb", None), 0),
                        )
                    )
                    recent_data_writes = recent_data_writes[-12:]
                else:
                    pass


        if watch_write_addr >= 0 and cycle >= watch_write_after_cycle and mem_req_h is not None:
            mem_req = _safe_int(mem_req_h, 0)
            mem_we = _safe_int(mem_we_h, 0)
            mem_gnt = _safe_int(mem_gnt_h, 0)
            if mem_req and mem_we and mem_gnt:
                mem_addr = _safe_int(mem_addr_h, 0)
                mem_be = _safe_int(mem_be_h, 0)
                mem_wdata = _safe_int(mem_wdata_h, 0)
                recent_mem_writes.append((cycle, mem_addr, mem_be, mem_wdata))
                recent_mem_writes = recent_mem_writes[-12:]
                watch_lo = watch_write_addr
                watch_hi = watch_write_addr + watch_write_size
                if _write_touches_range(mem_addr, mem_be, 8, watch_lo, watch_hi):
                    data_history = ", ".join(
                        f"{c}:0x{a:08x}/be{b:x}/0x{d:08x}/pc_id=0x{pid:08x}/pc_wb=0x{pwb:08x}"
                        for c, a, b, d, pid, pwb in recent_data_writes
                    )
                    mem_history = ", ".join(
                        f"{c}:0x{a:08x}/be{b:02x}/0x{d:016x}" for c, a, b, d in recent_mem_writes
                    )
                    read_history = ", ".join(
                        (
                            f"{rc}->{sc}:0x{a:08x}/0x{d:08x}"
                            f"/req_pc=0x{rpid:08x}/rsp_pc=0x{spid:08x}"
                        )
                        for rc, sc, a, d, rpid, _rpwb, spid, _spwb in recent_data_reads
                    )
                    pc_history = ", ".join(
                        f"{c}:id=0x{pid:08x}/wb=0x{pwb:08x}" for c, pid, pwb in recent_pcs
                    )
                    raise AssertionError(
                        "Watched memory range was written: "
                        f"cycle={cycle} addr=0x{mem_addr:08x} be=0x{mem_be:02x} "
                        f"wdata=0x{mem_wdata:016x} "
                        f"watch=0x{watch_lo:08x}..0x{watch_hi - 1:08x} "
                        f"ibex_pc_id=0x{_safe_int(getattr(ibex_core_h, 'pc_id', None), 0):08x} "
                        f"ibex_pc_wb=0x{_safe_int(getattr(ibex_core_h, 'pc_wb', None), 0):08x} "
                        f"data_addr=0x{_safe_int(platform.data_addr, 0):08x} "
                        f"data_be=0x{_safe_int(platform.data_be, 0):x} "
                        f"data_wdata=0x{_safe_int(platform.data_wdata, 0):08x} "
                        f"recent_pcs=[{pc_history}] "
                        f"recent_data_reads=[{read_history}] "
                        f"recent_data_writes=[{data_history}] "
                        f"recent_mem_writes=[{mem_history}]"
                    )

        if platform is not None and force_debug_cycle >= 0:
            data_req = _safe_int(platform.data_req, 0)
            data_gnt = _safe_int(platform.data_gnt, 0)
            data_we = _safe_int(platform.data_we, 0)
            data_addr = _safe_int(platform.data_addr, 0)
            if data_req and data_gnt and data_we and data_addr == 0x100:
                debug_halted_write_seen = True
                dut._log.info("debug-diag: observed HALTED write at cycle=%d", cycle)
            if cva6_debug_visible:
                cva6_debug_mode = _safe_int(cva6_debug_mode_h, 0)
                aw_fire = (
                    _safe_int(cva6_axi_aw_valid_h, 0)
                    and _safe_int(cva6_axi_aw_ready_h, 0)
                )
                w_fire = (
                    _safe_int(cva6_axi_w_valid_h, 0)
                    and _safe_int(cva6_axi_w_ready_h, 0)
                )
                aw_addr = _safe_int(cva6_axi_aw_addr_h, 0)
                if cva6_debug_mode and aw_fire and (aw_addr & 0xFFF) == 0x100:
                    cva6_debug_aw_halted_seen = True
                    cva6_debug_aw_halted_addr = aw_addr
                if cva6_debug_mode and w_fire:
                    cva6_debug_w_seen = True
                if (
                    not debug_halted_write_seen
                    and cva6_debug_aw_halted_seen
                    and cva6_debug_w_seen
                ):
                    debug_halted_write_seen = True
                    dut._log.info(
                        "debug-diag: observed CVA6 AXI HALTED write at cycle=%d addr=0x%08x",
                        cycle,
                        cva6_debug_aw_halted_addr,
                    )
            if forced_debug_released and cycle > force_debug_cycle + force_debug_cycles + force_debug_done_cycles:
                if debug_halted_write_seen:
                    return
                raise AssertionError("Forced debug_req did not produce a HALTED debug-ROM write")

        if (
            trace_armed
            and
            trace_uart
            and trace_count < trace_limit
            and uart_apb_req is not None
            and hasattr(uart_apb_req, "psel")
        ):
            psel = _safe_int(uart_apb_req.psel, 0)
            penable = _safe_int(uart_apb_req.penable, 0)
            pwrite = _safe_int(uart_apb_req.pwrite, 0)
            if psel and penable and pwrite:
                dut._log.info(
                    "uart cycle=%d paddr=0x%08x pstrb=0x%x pwdata=0x%08x",
                    cycle,
                    _safe_int(uart_apb_req.paddr, 0),
                    _safe_int(uart_apb_req.pstrb, 0),
                    _safe_int(uart_apb_req.pwdata, 0),
                )
                trace_count += 1

        if int(dut.sim_print_valid.value):
            char = chr(int(dut.sim_print_data.value) & 0xFF)
            captured.append(char)
            line_buffer.append(char)
            current = "".join(captured)
            if trace_after_uart and not trace_after_uart_seen and trace_after_uart in current:
                dut._log.info("trace trigger: observed UART text: %s", trace_after_uart)
                trace_armed = True
                trace_after_uart_seen = True
            if expect_uart and expect_uart in current:
                dut._log.info("SW emitted expected UART text: %s", expect_uart)
                return
            if char == "\n":
                dut._log.info("SW: %s", "".join(line_buffer).rstrip("\n"))
                line_buffer.clear()
        else:
            current = "".join(captured)

        if int(dut.sim_status_valid.value):
            status_code = int(dut.sim_status_code.value)
            status_pass = bool(int(dut.sim_status_pass.value))
            if line_buffer:
                dut._log.info("SW: %s", "".join(line_buffer))
                line_buffer.clear()
            if status_pass:
                dut._log.info("SW reported PASS with status 0x%08x", status_code)
                return
            raise AssertionError(
                f"Software reported FAIL with status 0x{status_code:08x}. "
                f"Captured: {current!r}"
            )

    current = "".join(captured)
    if line_buffer:
        dut._log.info("SW: %s", "".join(line_buffer))
    raise AssertionError(
        "Timed out waiting for software to report PASS/FAIL via sim_ctrl. "
        f"Captured: {current!r}"
    )
