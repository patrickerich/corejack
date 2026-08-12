// SPDX-License-Identifier: Apache-2.0
//
module soc_top #(
  parameter int unsigned CoreType = platform_pkg::CoreIbex,
  parameter type apb_req_t = soc_bus_pkg::soc_apb_req_t,
  parameter type apb_rsp_t = soc_bus_pkg::soc_apb_resp_t,
  parameter bit EnablePlatform = 1'b0,
  parameter logic [31:0] DebugBaseAddr = 32'h0000_0000,
  parameter logic [31:0] ClintBaseAddr = 32'h0200_0000,
  parameter logic [31:0] DmaBaseAddr = 32'h0100_0000,
  parameter logic [31:0] PlicBaseAddr = 32'h0C00_0000,
  parameter logic [31:0] UartBaseAddr = 32'h1000_0000,
  parameter logic [31:0] RamBaseAddr = 32'h8000_0000,
  parameter int unsigned RamWords = 262144,
  parameter bit EnableUartLoader = 1'b0,
  parameter int unsigned UartLoaderClockHz = 25_000_000,
  parameter int unsigned UartLoaderBaud = 115_200,
  parameter string MemInitPath = "",
  parameter mem_ss_pkg::mem_impl_e MemImpl = mem_ss_pkg::MemImplModel,
  // SRAM banking is a designer's choice. The default of 8 matches the seven
  // ports that drive soc_mem_ss (two native 32-bit CPU ports plus five 64-bit
  // ports), so concurrent streams rarely collide on a bank; soc_mem_ss is
  // generic over NumBanks. The value itself lives in mem_ss_pkg because the
  // software build reads it from there to split the bank_<n>.hex preload
  // images - override this parameter and the images stop matching.
  parameter int unsigned MemNumBanks = mem_ss_pkg::MemNumBanksDefault
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  apb_req_t apb_req_i,
  output apb_rsp_t apb_rsp_o,
  input  logic uart_rx_i,
  output logic uart_tx_o,
  input  logic jtag_tck_i,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  output logic dmactive_o,
  output logic debug_req_o,
  output logic alert_minor_o,
  output logic alert_major_internal_o,
  output logic alert_major_bus_o,
  output logic core_sleep_o
);
  import soc_bus_pkg::*;
  import dm::*;
  import mem_ss_pkg::*;

  if (!EnablePlatform) begin : gen_stub
    // Stub-only address windows used by the smoke testbench (`tb/test_smoke.py`).
    // The real platform branch below builds its address map from module
    // parameters and does not use these constants.
    localparam logic [31:0] Uart0Base  = 32'h1000_0000;
    localparam logic [31:0] Uart0Size  = 32'h0000_1000;
    localparam logic [31:0] Debug0Base = 32'hFFFF_0000;
    localparam logic [31:0] Debug0Size = 32'h0001_0000;

    logic [31:0] accel_cfg_reg_q;
    logic [31:0] debug_status_q;
    logic        apb_hit_uart;
    logic        apb_hit_debug;
    logic        apb_access;
    apb_rsp_t    apb_rsp;

    assign apb_hit_uart  = (apb_req_i.paddr - Uart0Base) < Uart0Size;
    assign apb_hit_debug = (apb_req_i.paddr - Debug0Base) < Debug0Size;
    assign apb_access    = apb_req_i.psel && apb_req_i.penable;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        accel_cfg_reg_q <= '0;
        debug_status_q  <= 32'hD6B0_0001;
      end else if (apb_access && apb_req_i.pwrite && apb_hit_uart) begin
        accel_cfg_reg_q <= apb_req_i.pwdata;
      end
    end

    always_comb begin
      apb_rsp = '{default: '0};
      apb_rsp.pready = 1'b1;

      if (apb_access && !apb_req_i.pwrite) begin
        if (apb_hit_uart) begin
          apb_rsp.prdata = accel_cfg_reg_q;
        end else if (apb_hit_debug) begin
          apb_rsp.prdata = debug_status_q;
        end else begin
          apb_rsp.pslverr = 1'b1;
        end
      end
    end

    assign apb_rsp_o                = apb_rsp;
    assign uart_tx_o                = 1'b1;
    assign jtag_tdo_o               = 1'b0;
    assign dmactive_o               = 1'b0;
    assign debug_req_o              = 1'b0;
    assign alert_minor_o            = 1'b0;
    assign alert_major_internal_o   = 1'b0;
    assign alert_major_bus_o        = 1'b0;
    assign core_sleep_o             = 1'b0;
  end else begin : gen_platform
    localparam logic [31:0] DebugSize = 32'h0000_1000;
    localparam logic [31:0] ClintSize = 32'h0001_0000;
    localparam logic [31:0] UartSize = 32'h0000_1000;
    localparam logic [31:0] RamSize = RamWords * 4;
    localparam logic [31:0] DmHaltAddr = DebugBaseAddr + 32'h0000_0800;
    localparam logic [31:0] DmExceptionAddr = DebugBaseAddr + 32'h0000_0810;
    localparam logic [31:0] DmRomBaseSelect = 32'h0000_1000;
    // soc_mem_ss has two symmetric port groups. The five 64-bit ports are:
    // 0 = xbar RAM read engine, 1 = xbar RAM write engine (independent so a read
    // and a write hit different banks the same cycle), 2 = optional UART SRAM
    // loader, 3/4 = iDMA dedicated read/write engines. The two 32-bit ports are
    // the RV32 core's data (0) and instruction (1) direct RAM ports, routed off
    // the data/instruction OBI and connected natively (no 32->64 bridge), so the
    // memory subsystem performs the lane select. Only the RV32 core path drives
    // the 32-bit ports; the CVA6 path leaves the core OBI idle.
    localparam int unsigned MemInitPorts = 5;   // 64-bit ports only
    localparam int unsigned MemPorts32   = 2;   // native 32-bit CPU ports
    localparam logic [31:0] DmaSize = 32'h0000_1000;
    // The PLIC window spans the full standard layout (context block at
    // +0x200000), hence 4 MiB.
    localparam logic [31:0] PlicSize = 32'h0040_0000;
    // PLIC source IDs are 1-based; bit i of the source vector is ID i+1.
    // ID 1: UART. ID 2: iDMA completion interrupt, driven from the accelerator
    // socket (i_dma_socket.irq_o; see plic_irq_sources below).
    localparam int unsigned PlicNumSources = 2;
    // Three xbar initiators: core instruction, core data, debug SBA. The iDMA
    // is no longer an xbar initiator - its data path has dedicated soc_mem_ss
    // ports (see i_dma_axi_to_mem); only its CSR leg uses the fabric (APB).
    localparam int unsigned CoreAxiPorts = 3;
    localparam int unsigned FabricAxiPorts = 6;
    // System crossbar configuration. Replaces the former single-outstanding
    // soc_axi_arbiter + soc_axi_demux pair: per-target arbitration with up to
    // MaxTrans outstanding so independent initiators no longer serialize. Cores
    // emit single-beat, non-atomic traffic (no A extension), so ATOPs are off.
    // CUT_ALL_AX registers the AW/AR channels at both crossbar boundaries:
    // with a fully combinational crossbar, the valid->ready couplings of the
    // target adapters and the iDMA backend compose into a structural
    // combinational loop (flagged by Vivado DRC LUTLP-1); the AX cuts break
    // it and relax timing at the cost of one cycle of address latency.
    localparam axi_pkg::xbar_cfg_t FabricXbarCfg = '{
      NoSlvPorts:         CoreAxiPorts,
      NoMstPorts:         FabricAxiPorts,
      MaxMstTrans:        4,
      MaxSlvTrans:        4,
      FallThrough:        1'b0,
      LatencyMode:        axi_pkg::CUT_ALL_AX,
      PipelineStages:     32'd0,
      AxiIdWidthSlvPorts: soc_bus_pkg::AxiIdWidth,
      AxiIdUsedSlvPorts:  soc_bus_pkg::AxiIdWidth,
      UniqueIds:          1'b0,
      AxiAddrWidth:       soc_bus_pkg::AxiAddrWidth,
      AxiDataWidth:       soc_bus_pkg::AxiDataWidth,
      NoAddrRules:        FabricAxiPorts
    };
    localparam int unsigned MemDataWidth = 64;
    localparam int unsigned MemBytesPerWord = MemDataWidth / 8;
    localparam int unsigned MemWords = RamWords / 2;
    localparam dm::hartinfo_t HartInfo = '{
      zero1:      '0,
      nscratch:   4'd2,
      zero0:      '0,
      dataaccess: 1'b1,
      datasize:   dm::DataCount,
      dataaddr:   dm::DataAddr
    };

    logic ndmreset;
    logic ndmreset_ack;
    logic core_rst_ni;
    logic core_init_ni;
    logic core_init_ni_q;
    logic ndmreset_pending_q;
    logic core_debug_unavailable;
    logic uart_loader_active;
    logic uart_loader_tx;
    logic apb_uart_tx;
    logic          dmi_rst_n;
    dm::dmi_req_t  dmi_req;
    dm::dmi_resp_t dmi_resp;
    logic          dmi_req_valid;
    logic          dmi_req_ready;
    logic          dmi_resp_valid;
    logic          dmi_resp_ready;

    logic          dm_device_req;
    logic          dm_device_we;
    logic [63:0]   dm_device_addr;
    logic [7:0]    dm_device_be;
    logic [63:0]   dm_device_wdata;
    logic [63:0]   dm_device_rdata;

    logic          sba_req;
    logic          sba_we;
    logic [63:0]   sba_addr;
    logic [7:0]    sba_be;
    logic [63:0]   sba_wdata;
    logic          sba_gnt;
    logic          sba_r_valid;
    logic          sba_r_ready;
    logic          sba_r_err;
    logic [63:0]   sba_r_rdata;

    logic          core_instr_req;
    logic          core_instr_gnt;
    logic          core_instr_rvalid;
    logic [31:0]   core_instr_addr;
    logic [31:0]   core_instr_rdata;
    logic          core_instr_err;

    logic          instr_req;
    logic          instr_gnt;
    logic          instr_rvalid;
    logic          instr_rready;
    logic [31:0]   instr_addr;
    logic [31:0]   instr_rdata;
    logic          instr_err;

    logic          core_data_req;
    logic          core_data_gnt;
    logic          core_data_rvalid;
    logic          core_data_we;
    logic [3:0]    core_data_be;
    logic [31:0]   core_data_addr;
    logic [31:0]   core_data_wdata;
    logic [31:0]   core_data_rdata;
    logic          core_data_err;

    logic          data_req;
    logic          data_gnt;
    logic          data_rvalid;
    logic          data_rready;
    logic          data_we;
    logic [3:0]    data_be;
    logic [31:0]   data_addr;
    logic [31:0]   data_wdata;
    logic [31:0]   data_rdata;
    logic          data_err;

    logic [MemInitPorts-1:0]                      mem_init_req;
    logic [MemInitPorts-1:0]                      mem_init_we;
    logic [MemInitPorts-1:0][31:0]                mem_init_addr;
    logic [MemInitPorts-1:0][MemDataWidth-1:0]    mem_init_wdata;
    logic [MemInitPorts-1:0][MemBytesPerWord-1:0] mem_init_be;
    logic [MemInitPorts-1:0]                      mem_init_gnt;
    logic [MemInitPorts-1:0]                      mem_init_rvalid;
    logic [MemInitPorts-1:0][MemDataWidth-1:0]    mem_init_rdata;
    logic [MemInitPorts-1:0]                      mem_init_err;
    logic [MemInitPorts-1:0]                      mem_axi_rready;

    // Native 32-bit CPU memory ports: index 0 = core data, 1 = core instruction.
    logic [MemPorts32-1:0]        mem32_req;
    logic [MemPorts32-1:0]        mem32_gnt;
    logic [MemPorts32-1:0]        mem32_we;
    logic [MemPorts32-1:0][31:0]  mem32_addr;
    logic [MemPorts32-1:0][31:0]  mem32_wdata;
    logic [MemPorts32-1:0][3:0]   mem32_be;
    logic [MemPorts32-1:0]        mem32_rvalid;
    logic [MemPorts32-1:0]        mem32_rready;
    logic [MemPorts32-1:0][31:0]  mem32_rdata;
    logic [MemPorts32-1:0]        mem32_err;
    soc_axi_req_t [CoreAxiPorts-1:0]              core_axi_req;
    soc_axi_resp_t [CoreAxiPorts-1:0]             core_axi_rsp;
    soc_axi_req_t                                 instr_axi_req;
    soc_axi_resp_t                                instr_axi_rsp;
    soc_axi_req_t                                 data_axi_req;
    soc_axi_resp_t                                data_axi_rsp;
    soc_axi_req_t                                 cva6_axi_req;
    soc_axi_resp_t                                cva6_axi_rsp;
    // Target ports carry the wider crossbar master-side ID (`axi_xbar` prepends
    // the initiator index to the AXI ID); the target adapters are typed to match.
    soc_axi_mst_req_t [FabricAxiPorts-1:0]        target_axi_req;
    soc_axi_mst_resp_t [FabricAxiPorts-1:0]       target_axi_rsp;
    axi_pkg::xbar_rule_64_t [FabricAxiPorts-1:0]  fabric_addr_map;

    soc_apb_req_t  uart_apb_req;
    soc_apb_resp_t uart_apb_rsp;
    soc_reg_req_t  clint_reg_req;
    soc_reg_rsp_t  clint_reg_rsp;
    soc_apb_req_t  dma_apb_req;
    soc_apb_resp_t dma_apb_rsp;
    soc_reg_req_t  plic_reg_req;
    soc_reg_rsp_t  plic_reg_rsp;
    apb_rsp_t      apb_rsp;
    logic [PlicNumSources-1:0] plic_irq_sources;
    logic          plic_irq;
    logic          uart_irq;
    logic [1:0]    clint_timer_irq;
    logic [1:0]    clint_ipi;
    logic          clint_rtc_q;

`ifndef SYNTHESIS
    for (genvar i = 0; i < CoreAxiPorts; i++) begin : gen_core_axi_checkers
      soc_axi_protocol_checker i_axi_checker (
        .clk_i,
        .rst_ni,
        .req_i (core_axi_req[i]),
        .rsp_i (core_axi_rsp[i])
      );
    end

    // No single shared fabric stream exists anymore: `axi_xbar` decodes per
    // initiator and arbitrates per target, so the per-target checkers (typed to
    // the wider master-side AXI) cover the fabric outputs.
    for (genvar i = 0; i < FabricAxiPorts; i++) begin : gen_target_axi_checkers
      soc_axi_protocol_checker #(
        .req_t         (soc_axi_mst_req_t),
        .rsp_t         (soc_axi_mst_resp_t),
        .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
        .axi_w_chan_t  (soc_axi_mst_w_chan_t),
        .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
        .axi_b_chan_t  (soc_axi_mst_b_chan_t),
        .axi_r_chan_t  (soc_axi_mst_r_chan_t)
      ) i_axi_checker (
        .clk_i,
        .rst_ni,
        .req_i (target_axi_req[i]),
        .rsp_i (target_axi_rsp[i])
      );
    end

`endif

    // RAM geometry validation. These are generate-scope elaboration tasks, not
    // an `initial` block under `ifndef SYNTHESIS`: a bad geometry silently
    // advertises a RamSize larger than the memory actually instantiated
    // (WordsPerBank truncates), so synthesis-only flows have to fail loudly too
    // rather than build the broken hardware. Same reasoning as soc_mem_ss's
    // NumBanks check.
    if ((RamWords % 2) != 0) begin : gen_validate_ram_words
      $fatal(1, "soc_top: RamWords must be even for the 64-bit SRAM path");
    end
    if ((MemWords % MemNumBanks) != 0) begin : gen_validate_mem_banks
      $fatal(1, "soc_top: 64-bit SRAM word count must divide evenly across banks");
    end

    // Core-only reset: ndmreset / the UART loader reset the core while the
    // debug module, fabric, and memory stay live (required for SBA during
    // ndmreset). The bus-side blocks that hold core-initiated transaction
    // state (OBI buffers, routers, obi-to-axi bridges) deliberately stay on
    // rst_ni: their response inputs are always-ready (s_rready tied high), so
    // in-flight responses drain during the multi-cycle window between reset
    // assertion and rstgen's synchronized release, leaving no stale state.
    rstgen i_rstgen_core (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni & ~ndmreset & ~uart_loader_active),
      .test_mode_i (1'b0),
      .rst_no      (core_rst_ni),
      .init_no     (core_init_ni)
    );

    // ndmreset acknowledge: rstgen releases core_init_ni several cycles after
    // ndmreset deasserts, so a sticky pending flag (not a delayed ndmreset
    // sample) must qualify the core_init_ni rising edge - the debug module
    // sets dmstatus.{all,any}havereset only on this pulse.
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        core_init_ni_q    <= 1'b0;
        ndmreset_pending_q <= 1'b0;
        ndmreset_ack      <= 1'b0;
      end else begin
        core_init_ni_q <= core_init_ni;
        ndmreset_ack   <= ndmreset_pending_q && core_init_ni && !core_init_ni_q;
        if (ndmreset) begin
          ndmreset_pending_q <= 1'b1;
        end else if (core_init_ni && !core_init_ni_q) begin
          ndmreset_pending_q <= 1'b0;
        end
      end
    end

    // Rule bounds are widened explicitly: the xbar rules are 64-bit and the
    // base + size sums must not wrap in 32-bit arithmetic.
    assign fabric_addr_map = '{
      '{idx: 0, start_addr: {32'h0, RamBaseAddr},
                end_addr:   {32'h0, RamBaseAddr} + {32'h0, RamSize}},
      '{idx: 1, start_addr: {32'h0, UartBaseAddr},
                end_addr:   {32'h0, UartBaseAddr} + {32'h0, UartSize}},
      '{idx: 2, start_addr: {32'h0, DebugBaseAddr},
                end_addr:   {32'h0, DebugBaseAddr} + {32'h0, DebugSize}},
      '{idx: 3, start_addr: {32'h0, ClintBaseAddr},
                end_addr:   {32'h0, ClintBaseAddr} + {32'h0, ClintSize}},
      '{idx: 4, start_addr: {32'h0, DmaBaseAddr},
                end_addr:   {32'h0, DmaBaseAddr} + {32'h0, DmaSize}},
      '{idx: 5, start_addr: {32'h0, PlicBaseAddr},
                end_addr:   {32'h0, PlicBaseAddr} + {32'h0, PlicSize}}
    };

    if (CoreType == platform_pkg::CoreCva6) begin : gen_cva6_core_path
      assign core_axi_req[1] = '0;
      assign instr_axi_rsp   = '0;
      assign data_axi_rsp    = '0;

      // CVA6 is the only core that is itself the AXI initiator, so a core-only
      // reset can orphan a transaction the crossbar has already accepted. The
      // RV32 path cannot: its bus-side blocks (OBI buffers, obi-to-axi bridges)
      // sit on rst_ni and own the fabric transaction, and the buffers' core-side
      // s_rready_i is tied high so responses always retire. This is the AXI
      // analogue of that arrangement - an isolation stage on rst_ni that owns
      // the outstanding transactions, issues no new ones while the core is down,
      // and retires in-flight responses without the core (see the forced
      // response readies below), so the fabric is never left waiting.
      //
      // The window is held until axi_isolate reports the drain complete, not
      // merely while core_rst_ni is low, so a slow response cannot land on a
      // freshly released core. uart_loader_active also gates core_rst_ni, but
      // the loader only serves cores without a debug interface (serv, picorv32,
      // cvw) and never CVA6, so ~core_rst_ni covers that path.
      logic         cva6_isolate;
      logic         cva6_isolated;
      logic         cva6_isolate_q;
      soc_axi_req_t cva6_iso_req;

      assign cva6_isolate = ~core_rst_ni | ndmreset_pending_q |
                            (cva6_isolate_q & ~cva6_isolated);

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          cva6_isolate_q <= 1'b0;
        end else begin
          cva6_isolate_q <= cva6_isolate;
        end
      end

      // The AXI analogue of the OBI buffers' s_rready_i tie-high: while the core
      // is down, responses are accepted regardless of it, so axi_isolate's drain
      // completes instead of stalling on a reset core that holds its readies low.
      always_comb begin
        cva6_iso_req         = cva6_axi_req;
        cva6_iso_req.r_ready = cva6_axi_req.r_ready | cva6_isolate;
        cva6_iso_req.b_ready = cva6_axi_req.b_ready | cva6_isolate;
      end

      axi_isolate #(
        // CVA6's outstanding capacity is bounded well below this by
        // cva6_corejack_config_pkg (2 load-buffer entries, 4 outstanding stores,
        // 8 scoreboard entries) plus cache line fills. Oversizing only widens a
        // counter; undersizing would throttle the core.
        .NumPending           (32),
        // Block rather than error-terminate: between core_rst_ni release and the
        // isolate window closing, a stall is safer for a freshly reset core than
        // an injected decode error.
        .TerminateTransaction (1'b0),
        // The fabric runs without atomics (see FabricXbarCfg).
        .AtopSupport          (1'b0),
        .AxiAddrWidth         (soc_bus_pkg::AxiAddrWidth),
        .AxiDataWidth         (soc_bus_pkg::AxiDataWidth),
        .AxiIdWidth           (soc_bus_pkg::AxiIdWidth),
        .AxiUserWidth         ($bits(soc_bus_pkg::axi_user_t)),
        .axi_req_t            (soc_axi_req_t),
        .axi_resp_t           (soc_axi_resp_t)
      ) i_cva6_isolate (
        .clk_i,
        // rst_ni, not core_rst_ni: this stage must outlive the core reset.
        .rst_ni,
        .slv_req_i  (cva6_iso_req),
        .slv_resp_o (cva6_axi_rsp),
        .mst_req_o  (core_axi_req[0]),
        .mst_resp_i (core_axi_rsp[0]),
        .isolate_i  (cva6_isolate),
        .isolated_o (cva6_isolated)
      );

`ifndef SYNTHESIS
      // The drain must finish. It cannot if a write was committed on AW without
      // its W beat ever being sent, since axi_isolate waits on pending_w and
      // does not inject one. No regression issues ndmreset with CVA6 traffic in
      // flight today, so this watchdog is what would surface that corner.
      localparam int unsigned Cva6IsolateTimeout = 1024;
      int unsigned cva6_isolate_cnt_q;
      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
          cva6_isolate_cnt_q <= 0;
        end else if (!cva6_isolate) begin
          cva6_isolate_cnt_q <= 0;
        end else begin
          cva6_isolate_cnt_q <= cva6_isolate_cnt_q + 1;
          // Report once at the threshold rather than every cycle after it.
          if (cva6_isolate_cnt_q == Cva6IsolateTimeout) begin
            $error("soc_top: CVA6 AXI isolation did not drain within %0d cycles",
                   Cva6IsolateTimeout);
          end
        end
      end
`endif

      assign core_instr_req    = 1'b0;
      assign core_instr_addr   = '0;
      assign core_instr_rdata  = '0;
      assign core_instr_gnt    = 1'b0;
      assign core_instr_rvalid = 1'b0;
      assign core_instr_err    = 1'b0;

      assign instr_req    = 1'b0;
      assign instr_addr   = '0;
      assign instr_rready = 1'b1;

      assign core_data_req    = 1'b0;
      assign core_data_we     = 1'b0;
      assign core_data_be     = '0;
      assign core_data_addr   = '0;
      assign core_data_wdata  = '0;
      assign core_data_rdata  = '0;
      assign core_data_gnt    = 1'b0;
      assign core_data_rvalid = 1'b0;
      assign core_data_err    = 1'b0;

      assign data_req    = 1'b0;
      assign data_we     = 1'b0;
      assign data_be     = '0;
      assign data_addr   = '0;
      assign data_wdata  = '0;
      assign data_rready = 1'b1;

      corejack_cva6_axi_adapter #(
        .BootAddr        ({32'h0, RamBaseAddr} + 64'h80),
        .HartId          (64'h0),
        .DmBaseAddr      ({32'h0, DebugBaseAddr}),
        .DmHaltAddr      ({32'h0, DmHaltAddr}),
        .DmExceptionAddr ({32'h0, DmExceptionAddr})
      ) i_cva6_core (
        .clk_i,
        .rst_ni                 (core_rst_ni),
        .debug_req_i            (debug_req_o),
        .irq_software_i         (clint_ipi[0]),
        .irq_timer_i            (clint_timer_irq[0]),
        .irq_external_i         (plic_irq),
        .axi_req_o              (cva6_axi_req),
        .axi_rsp_i              (cva6_axi_rsp),
        .alert_minor_o          (alert_minor_o),
        .alert_major_internal_o (alert_major_internal_o),
        .alert_major_bus_o      (alert_major_bus_o),
        .debug_unavailable_o    (core_debug_unavailable),
        .core_sleep_o           (core_sleep_o)
      );
    end else begin : gen_rv32_core_path
      assign core_axi_req[0] = instr_axi_req;
      assign core_axi_req[1] = data_axi_req;
      assign instr_axi_rsp   = core_axi_rsp[0];
      assign data_axi_rsp    = core_axi_rsp[1];
      assign cva6_axi_rsp    = '0;

      corejack_core_region #(
        .CoreType        (CoreType),
        .BootAddr        (RamBaseAddr),
        .HartId          (32'h0),
        .DmBaseAddr      (DebugBaseAddr),
        .DmHaltAddr      (DmHaltAddr),
        .DmExceptionAddr (DmExceptionAddr)
      ) i_core_region (
        .clk_i                  (clk_i),
        .rst_ni                 (core_rst_ni),
        .debug_req_i            (debug_req_o),
        .irq_software_i         (clint_ipi[0]),
        .irq_timer_i            (clint_timer_irq[0]),
        .irq_external_i         (plic_irq),
        .irq_fast_i             ('0),
        .irq_nm_i               (1'b0),
        .instr_req_o            (core_instr_req),
        .instr_gnt_i            (core_instr_gnt),
        .instr_rvalid_i         (core_instr_rvalid),
        .instr_addr_o           (core_instr_addr),
        .instr_rdata_i          (core_instr_rdata),
        .instr_err_i            (core_instr_err),
        .data_req_o             (core_data_req),
        .data_gnt_i             (core_data_gnt),
        .data_rvalid_i          (core_data_rvalid),
        .data_we_o              (core_data_we),
        .data_be_o              (core_data_be),
        .data_addr_o            (core_data_addr),
        .data_wdata_o           (core_data_wdata),
        .data_rdata_i           (core_data_rdata),
        .data_err_i             (core_data_err),
        .alert_minor_o          (alert_minor_o),
        .alert_major_internal_o (alert_major_internal_o),
        .alert_major_bus_o      (alert_major_bus_o),
        .debug_unavailable_o    (core_debug_unavailable),
        .core_sleep_o           (core_sleep_o)
      );

      soc_obi_mem_buffer #(
        .AddrWidth    (32),
        .DataWidth    (32),
        .ReqFifoDepth (2),
        .RspFifoDepth (2)
      ) i_instr_buffer (
        .clk_i,
        .rst_ni,
        .s_req_i     (core_instr_req),
        .s_gnt_o     (core_instr_gnt),
        .s_we_i      (1'b0),
        .s_addr_i    (core_instr_addr),
        .s_wdata_i   ('0),
        .s_be_i      (4'hF),
        .s_rvalid_o  (core_instr_rvalid),
        .s_rready_i  (1'b1),
        .s_rdata_o   (core_instr_rdata),
        .s_err_o     (core_instr_err),
        .m_req_o     (instr_req),
        .m_gnt_i     (instr_gnt),
        .m_we_o      (),
        .m_addr_o    (instr_addr),
        .m_wdata_o   (),
        .m_be_o      (),
        .m_rvalid_i  (instr_rvalid),
        .m_rready_o  (instr_rready),
        .m_rdata_i   (instr_rdata),
        .m_err_i     (instr_err)
      );

      soc_obi_mem_buffer #(
        .AddrWidth    (32),
        .DataWidth    (32),
        .ReqFifoDepth (2),
        .RspFifoDepth (2)
      ) i_data_buffer (
        .clk_i,
        .rst_ni,
        .s_req_i     (core_data_req),
        .s_gnt_o     (core_data_gnt),
        .s_we_i      (core_data_we),
        .s_addr_i    (core_data_addr),
        .s_wdata_i   (core_data_wdata),
        .s_be_i      (core_data_be),
        .s_rvalid_o  (core_data_rvalid),
        .s_rready_i  (1'b1),
        .s_rdata_o   (core_data_rdata),
        .s_err_o     (core_data_err),
        .m_req_o     (data_req),
        .m_gnt_i     (data_gnt),
        .m_we_o      (data_we),
        .m_addr_o    (data_addr),
        .m_wdata_o   (data_wdata),
        .m_be_o      (data_be),
        .m_rvalid_i  (data_rvalid),
        .m_rready_o  (data_rready),
        .m_rdata_i   (data_rdata),
        .m_err_i     (data_err)
      );
    end

    // ------------------------------------------------------------------------
    // Instruction request router. Mirrors the data router: RAM-window fetches
    // take a dedicated soc_mem_ss native 32-bit port (mem32[1]), bypassing the xbar (and
    // its CUT_ALL_AX + soc_obi_to_axi + soc_axi_to_mem chain), so instruction
    // fetch runs concurrently with - and at lower latency than - the old xbar
    // path. Non-RAM fetches go through the xbar via core_axi_req[0]: in
    // practice the only non-RAM instruction fetches are from the debug-module
    // ROM at DebugBaseAddr (0x0) while the core is halted. The router is
    // read-only and single-outstanding across the two paths. CVA6 leaves the
    // instruction OBI idle (instr_req = 0), so both paths stay quiescent.
    // ------------------------------------------------------------------------
    logic        instr_is_ram;
    logic        instr_rt_busy_q;
    logic        instr_rt_sel_ram_q;
    logic        instr_rt_accept;
    logic        instr_to_ram;
    logic        instr_to_axi;
    logic        instr_sel_gnt;
    logic        instr_axi_gnt;
    logic        instr_axi_rvalid;
    logic        instr_axi_err;
    logic [31:0] instr_axi_rdata;
    logic        instr_mem_gnt;
    logic        instr_mem_rvalid;
    logic        instr_mem_err;
    logic [31:0] instr_mem_rdata;

    assign instr_is_ram    = (instr_addr >= RamBaseAddr) &&
                             (instr_addr < (RamBaseAddr + RamSize));
    assign instr_rt_accept = instr_req & ~instr_rt_busy_q;
    assign instr_to_ram    = instr_rt_accept & instr_is_ram;
    assign instr_to_axi    = instr_rt_accept & ~instr_is_ram;
    assign instr_sel_gnt   = instr_is_ram ? instr_mem_gnt : instr_axi_gnt;

    assign instr_gnt    = instr_rt_accept & instr_sel_gnt;
    assign instr_rvalid = instr_rt_busy_q &
                          (instr_rt_sel_ram_q ? instr_mem_rvalid : instr_axi_rvalid);
    assign instr_rdata  = instr_rt_sel_ram_q ? instr_mem_rdata : instr_axi_rdata;
    assign instr_err    = instr_rt_busy_q &
                          (instr_rt_sel_ram_q ? instr_mem_err : instr_axi_err);

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        instr_rt_busy_q    <= 1'b0;
        instr_rt_sel_ram_q <= 1'b0;
      end else if (!instr_rt_busy_q) begin
        if (instr_rt_accept && instr_sel_gnt) begin
          instr_rt_busy_q    <= 1'b1;
          instr_rt_sel_ram_q <= instr_is_ram;
        end
      end else if (instr_rvalid && instr_rready) begin
        instr_rt_busy_q <= 1'b0;
      end
    end

    soc_obi_to_axi i_instr_obi_to_axi (
      .clk_i,
      .rst_ni,
      .s_addr_i    (instr_addr),
      .s_wdata_i   ('0),
      .s_be_i      (4'hF),
      .s_we_i      (1'b0),
      .s_req_i     (instr_to_axi),
      .s_gnt_o     (instr_axi_gnt),
      .s_rvalid_o  (instr_axi_rvalid),
      .s_rready_i  (instr_rready),
      .s_rdata_o   (instr_axi_rdata),
      .s_err_o     (instr_axi_err),
      .m_axi_req_o (instr_axi_req),
      .m_axi_rsp_i (instr_axi_rsp)
    );

    // Instruction RAM fetches drive the native 32-bit memory port 1 directly:
    // the memory subsystem performs the 32-bit lane select on the 64-bit slice.
    assign mem32_req[1]    = instr_to_ram;
    assign mem32_we[1]     = 1'b0;
    assign mem32_addr[1]   = instr_addr;
    assign mem32_wdata[1]  = '0;
    assign mem32_be[1]     = 4'hF;
    assign mem32_rready[1] = instr_rready;
    assign instr_mem_gnt    = mem32_gnt[1];
    assign instr_mem_rvalid = mem32_rvalid[1];
    assign instr_mem_rdata  = mem32_rdata[1];
    assign instr_mem_err    = mem32_err[1];

    // ------------------------------------------------------------------------
    // Data request router. An initiator-side address decode on the core data
    // port sends RAM-window accesses to a dedicated soc_mem_ss native 32-bit
    // port (mem32[0]), bypassing the xbar, so CPU data and CPU instruction fetch land
    // on different memory ports and run concurrently instead of serializing
    // through the xbar's single RAM master port. Non-RAM data accesses (UART,
    // CLINT, PLIC, DMA CSR, debug ROM, decode misses) still go through the xbar
    // via core_axi_req[1]. The router is single-outstanding across the two
    // paths, so OBI responses stay in order without a reorder buffer;
    // back-to-back accesses to the same path are not blocked by the router
    // (each sub-bridge is itself single-outstanding). CVA6 leaves the data OBI
    // idle (data_req = 0), so both paths stay quiescent for it.
    // ------------------------------------------------------------------------
    logic        data_is_ram;
    logic        data_rt_busy_q;
    logic        data_rt_sel_ram_q;
    logic        data_rt_accept;
    logic        data_to_ram;
    logic        data_to_axi;
    logic        data_sel_gnt;
    logic        data_axi_gnt;
    logic        data_axi_rvalid;
    logic        data_axi_err;
    logic [31:0] data_axi_rdata;
    logic        data_mem_gnt;
    logic        data_mem_rvalid;
    logic        data_mem_err;
    logic [31:0] data_mem_rdata;

    assign data_is_ram    = (data_addr >= RamBaseAddr) &&
                            (data_addr < (RamBaseAddr + RamSize));
    assign data_rt_accept = data_req & ~data_rt_busy_q;
    assign data_to_ram    = data_rt_accept & data_is_ram;
    assign data_to_axi    = data_rt_accept & ~data_is_ram;
    assign data_sel_gnt   = data_is_ram ? data_mem_gnt : data_axi_gnt;

    assign data_gnt    = data_rt_accept & data_sel_gnt;
    assign data_rvalid = data_rt_busy_q &
                         (data_rt_sel_ram_q ? data_mem_rvalid : data_axi_rvalid);
    assign data_rdata  = data_rt_sel_ram_q ? data_mem_rdata : data_axi_rdata;
    assign data_err    = data_rt_busy_q &
                         (data_rt_sel_ram_q ? data_mem_err : data_axi_err);

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        data_rt_busy_q    <= 1'b0;
        data_rt_sel_ram_q <= 1'b0;
      end else if (!data_rt_busy_q) begin
        if (data_rt_accept && data_sel_gnt) begin
          data_rt_busy_q    <= 1'b1;
          data_rt_sel_ram_q <= data_is_ram;
        end
      end else if (data_rvalid && data_rready) begin
        data_rt_busy_q <= 1'b0;
      end
    end

    soc_obi_to_axi i_data_obi_to_axi (
      .clk_i,
      .rst_ni,
      .s_addr_i    (data_addr),
      .s_wdata_i   (data_wdata),
      .s_be_i      (data_be),
      .s_we_i      (data_we),
      .s_req_i     (data_to_axi),
      .s_gnt_o     (data_axi_gnt),
      .s_rvalid_o  (data_axi_rvalid),
      .s_rready_i  (data_rready),
      .s_rdata_o   (data_axi_rdata),
      .s_err_o     (data_axi_err),
      .m_axi_req_o (data_axi_req),
      .m_axi_rsp_i (data_axi_rsp)
    );

    // Data RAM accesses drive the native 32-bit memory port 0 directly.
    assign mem32_req[0]    = data_to_ram;
    assign mem32_we[0]     = data_we;
    assign mem32_addr[0]   = data_addr;
    assign mem32_wdata[0]  = data_wdata;
    assign mem32_be[0]     = data_be;
    assign mem32_rready[0] = data_rready;
    assign data_mem_gnt    = mem32_gnt[0];
    assign data_mem_rvalid = mem32_rvalid[0];
    assign data_mem_rdata  = mem32_rdata[0];
    assign data_mem_err    = mem32_err[0];

    soc_obi_to_axi #(
      .ObiAddrWidth (64),
      .ObiDataWidth (64)
    ) i_sba_obi_to_axi (
      .clk_i,
      .rst_ni,
      .s_addr_i    (sba_addr),
      .s_wdata_i   (sba_wdata),
      .s_be_i      (sba_be),
      .s_we_i      (sba_we),
      .s_req_i     (sba_req),
      .s_gnt_o     (sba_gnt),
      .s_rvalid_o  (sba_r_valid),
      .s_rready_i  (sba_r_ready),
      .s_rdata_o   (sba_r_rdata),
      .s_err_o     (sba_r_err),
      .m_axi_req_o (core_axi_req[2]),
      .m_axi_rsp_i (core_axi_rsp[2])
    );

    // iDMA system DMA, plugged in through the accelerator socket: the CSR
    // leg arrives as APB from fabric target port [4], the completion interrupt
    // lands on PLIC source 2, and the (burst-split, single-beat) AXI memory
    // manager drives a dedicated soc_axi_to_mem into soc_mem_ss (init ports
    // 3/4) - it is NOT an xbar initiator, so its RAM traffic runs concurrently
    // with the CPU's instead of sharing the xbar's single RAM master port. No
    // platform power controller exists yet, so the power-intent pins sit in the
    // static active state (asserted inside the adapter).
    accel_socket_if #(
      .mem_axi_req_t (soc_axi_req_t),
      .mem_axi_rsp_t (soc_axi_resp_t),
      .csr_apb_req_t (soc_apb_req_t),
      .csr_apb_rsp_t (soc_apb_resp_t)
    ) i_dma_socket ();

    assign i_dma_socket.clk      = clk_i;
    assign i_dma_socket.rst_n    = rst_ni;
    assign i_dma_socket.power_en = 1'b1;
    assign i_dma_socket.isolate  = 1'b0;
    assign i_dma_socket.retain   = 1'b0;
    assign i_dma_socket.clk_en   = 1'b1;
    assign i_dma_socket.csr_req  = dma_apb_req;
    assign dma_apb_rsp           = i_dma_socket.csr_rsp;

    corejack_idma_socket_adapter i_idma_socket_adapter (
      .sock (i_dma_socket.accel)
    );

    // Dedicated iDMA RAM path: its single-beat AXI memory manager drives its
    // own soc_mem_ss read/write init ports (3/4), bypassing the xbar so iDMA
    // RAM traffic does not contend with the CPU on the xbar's single RAM master
    // port. iDMA data is RAM-to-RAM; an out-of-RAM target errors cleanly via
    // soc_mem_ss's range check. (DMA to a non-RAM peripheral would need a
    // request route back onto the xbar; not provided - the iDMA is a memory
    // mover here.)
    soc_axi_to_mem #(
      .AddrWidth (32),
      .DataWidth (MemDataWidth)
    ) i_dma_axi_to_mem (
      .clk_i,
      .rst_ni,
      .s_axi_req_i     (i_dma_socket.mem_req),
      .s_axi_rsp_o     (i_dma_socket.mem_rsp),
      .mem_rd_req_o    (mem_init_req[3]),
      .mem_rd_we_o     (mem_init_we[3]),
      .mem_rd_addr_o   (mem_init_addr[3]),
      .mem_rd_wdata_o  (mem_init_wdata[3]),
      .mem_rd_be_o     (mem_init_be[3]),
      .mem_rd_gnt_i    (mem_init_gnt[3]),
      .mem_rd_rvalid_i (mem_init_rvalid[3]),
      .mem_rd_rready_o (mem_axi_rready[3]),
      .mem_rd_rdata_i  (mem_init_rdata[3]),
      .mem_rd_err_i    (mem_init_err[3]),
      .mem_wr_req_o    (mem_init_req[4]),
      .mem_wr_we_o     (mem_init_we[4]),
      .mem_wr_addr_o   (mem_init_addr[4]),
      .mem_wr_wdata_o  (mem_init_wdata[4]),
      .mem_wr_be_o     (mem_init_be[4]),
      .mem_wr_gnt_i    (mem_init_gnt[4]),
      .mem_wr_rvalid_i (mem_init_rvalid[4]),
      .mem_wr_rready_o (mem_axi_rready[4]),
      .mem_wr_err_i    (mem_init_err[4])
    );

    // System crossbar: the three initiators (core instruction, core data,
    // debug SBA) decode per port and arbitrate per target. Decode misses land
    // on the xbar's built-in error slave (no explicit default master port).
    // The iDMA is not here - its data path has dedicated soc_mem_ss ports.
    axi_xbar #(
      .Cfg           (FabricXbarCfg),
      .ATOPs         (1'b0),
      .slv_aw_chan_t (soc_axi_aw_chan_t),
      .mst_aw_chan_t (soc_axi_mst_aw_chan_t),
      .w_chan_t      (soc_axi_w_chan_t),
      .slv_b_chan_t  (soc_axi_b_chan_t),
      .mst_b_chan_t  (soc_axi_mst_b_chan_t),
      .slv_ar_chan_t (soc_axi_ar_chan_t),
      .mst_ar_chan_t (soc_axi_mst_ar_chan_t),
      .slv_r_chan_t  (soc_axi_r_chan_t),
      .mst_r_chan_t  (soc_axi_mst_r_chan_t),
      .slv_req_t     (soc_axi_req_t),
      .slv_resp_t    (soc_axi_resp_t),
      .mst_req_t     (soc_axi_mst_req_t),
      .mst_resp_t    (soc_axi_mst_resp_t),
      .rule_t        (axi_pkg::xbar_rule_64_t)
    ) i_fabric_axi_xbar (
      .clk_i,
      .rst_ni,
      .test_i                (1'b0),
      .slv_ports_req_i       (core_axi_req),
      .slv_ports_resp_o      (core_axi_rsp),
      .mst_ports_req_o       (target_axi_req),
      .mst_ports_resp_i      (target_axi_rsp),
      .addr_map_i            (fabric_addr_map),
      .en_default_mst_port_i ('0),
      .default_mst_port_i    ('0)
    );

    soc_axi_to_mem #(
      .AddrWidth     (32),
      .DataWidth     (MemDataWidth),
      // The crossbar never presents more than MaxMstTrans transactions to one
      // master port, so depth beyond that is unreachable on this leg. The iDMA
      // leg keeps the deeper default because it is not behind the crossbar.
      .MaxOutstanding (FabricXbarCfg.MaxMstTrans),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_mem (
      .clk_i,
      .rst_ni,
      .s_axi_req_i  (target_axi_req[0]),
      .s_axi_rsp_o  (target_axi_rsp[0]),
      // Read engine -> init port 0, write engine -> init port 1, so a read and
      // a write to different banks proceed concurrently in soc_mem_ss.
      .mem_rd_req_o    (mem_init_req[0]),
      .mem_rd_we_o     (mem_init_we[0]),
      .mem_rd_addr_o   (mem_init_addr[0]),
      .mem_rd_wdata_o  (mem_init_wdata[0]),
      .mem_rd_be_o     (mem_init_be[0]),
      .mem_rd_gnt_i    (mem_init_gnt[0]),
      .mem_rd_rvalid_i (mem_init_rvalid[0]),
      .mem_rd_rready_o (mem_axi_rready[0]),
      .mem_rd_rdata_i  (mem_init_rdata[0]),
      .mem_rd_err_i    (mem_init_err[0]),
      .mem_wr_req_o    (mem_init_req[1]),
      .mem_wr_we_o     (mem_init_we[1]),
      .mem_wr_addr_o   (mem_init_addr[1]),
      .mem_wr_wdata_o  (mem_init_wdata[1]),
      .mem_wr_be_o     (mem_init_be[1]),
      .mem_wr_gnt_i    (mem_init_gnt[1]),
      .mem_wr_rvalid_i (mem_init_rvalid[1]),
      .mem_wr_rready_o (mem_axi_rready[1]),
      .mem_wr_err_i    (mem_init_err[1])
    );

    if (EnableUartLoader) begin : gen_uart_sram_loader
      soc_uart_sram_loader #(
        .ClockHz   (UartLoaderClockHz),
        .Baud      (UartLoaderBaud),
        .AddrWidth (32),
        .DataWidth (MemDataWidth)
      ) i_uart_sram_loader (
        .clk_i,
        .rst_ni,
        .enable_i      (1'b1),
        .uart_rx_i     (uart_rx_i),
        .uart_tx_o     (uart_loader_tx),
        .active_o      (uart_loader_active),
        .done_o        (),
        .mem_req_o     (mem_init_req[2]),
        .mem_we_o      (mem_init_we[2]),
        .mem_addr_o    (mem_init_addr[2]),
        .mem_wdata_o   (mem_init_wdata[2]),
        .mem_be_o      (mem_init_be[2]),
        .mem_gnt_i     (mem_init_gnt[2]),
        .mem_rvalid_i  (mem_init_rvalid[2]),
        .mem_rready_o  (mem_axi_rready[2]),
        .mem_err_i     (mem_init_err[2])
      );
    end else begin : gen_no_uart_sram_loader
      assign uart_loader_active = 1'b0;
      assign uart_loader_tx     = 1'b1;
      assign mem_init_req[2]    = 1'b0;
      assign mem_init_we[2]     = 1'b0;
      assign mem_init_addr[2]   = '0;
      assign mem_init_wdata[2]  = '0;
      assign mem_init_be[2]     = '0;
      assign mem_axi_rready[2]  = 1'b1;
    end

    soc_axi_to_apb #(
      .BaseAddr      (UartBaseAddr),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_uart_apb (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[1]),
      .s_axi_rsp_o (target_axi_rsp[1]),
      .m_apb_req_o (uart_apb_req),
      .m_apb_rsp_i (uart_apb_rsp)
    );

    soc_axi_to_dm #(
      .BaseAddr      (DebugBaseAddr),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_dm (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[2]),
      .s_axi_rsp_o (target_axi_rsp[2]),
      .dm_req_o    (dm_device_req),
      .dm_we_o     (dm_device_we),
      .dm_addr_o   (dm_device_addr),
      .dm_be_o     (dm_device_be),
      .dm_wdata_o  (dm_device_wdata),
      .dm_rdata_i  (dm_device_rdata)
    );

    soc_axi_to_reg #(
      .BaseAddr      (ClintBaseAddr),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_clint_reg (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[3]),
      .s_axi_rsp_o (target_axi_rsp[3]),
      .m_reg_req_o (clint_reg_req),
      .m_reg_rsp_i (clint_reg_rsp)
    );

    // The DMA window is served over APB: the socket's CSR leg speaks the
    // peripheral-subsystem protocol, and the engine-side conversion to the
    // iDMA's register interface happens inside the socket adapter.
    soc_axi_to_apb #(
      .BaseAddr      (DmaBaseAddr),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_dma_apb (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[4]),
      .s_axi_rsp_o (target_axi_rsp[4]),
      .m_apb_req_o (dma_apb_req),
      .m_apb_rsp_i (dma_apb_rsp)
    );

    soc_axi_to_reg #(
      .BaseAddr      (PlicBaseAddr),
      .axi_req_t     (soc_axi_mst_req_t),
      .axi_resp_t    (soc_axi_mst_resp_t),
      .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
      .axi_w_chan_t  (soc_axi_mst_w_chan_t),
      .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
      .axi_b_chan_t  (soc_axi_mst_b_chan_t),
      .axi_r_chan_t  (soc_axi_mst_r_chan_t)
    ) i_axi_to_plic_reg (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[5]),
      .s_axi_rsp_o (target_axi_rsp[5]),
      .m_reg_req_o (plic_reg_req),
      .m_reg_rsp_i (plic_reg_rsp)
    );

    // Platform interrupt controller: aggregates peripheral interrupts onto
    // the one external-interrupt line every core contract provides (MEIP).
    // Source IDs: 1 = UART, 2 = iDMA transfer completion (sticky flag in the
    // socket adapter, W1C at DMA window offset 0xF00).
    assign plic_irq_sources = {i_dma_socket.irq_o, uart_irq};

    soc_plic #(
      .NumSources (PlicNumSources)
    ) i_plic (
      .clk_i,
      .rst_ni,
      .reg_req_i     (plic_reg_req),
      .reg_rsp_o     (plic_reg_rsp),
      .irq_sources_i (plic_irq_sources),
      .irq_o         (plic_irq)
    );

    soc_mem_ss #(
      .NumPorts32(MemPorts32),
      .NumPorts64(MemInitPorts),
      .NumBanks(MemNumBanks),
      .MemDataWidth(MemDataWidth),
      .AddrWidth(32),
      .WordsPerBank(MemWords / MemNumBanks),
      .BaseAddr(RamBaseAddr),
      .MemInitPath(MemInitPath),
      .MemImpl(MemImpl)
    ) i_mem_ss (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      // Native 32-bit CPU ports (0 = data, 1 = instruction).
      .req32_i(mem32_req), .gnt32_o(mem32_gnt), .we32_i(mem32_we),
      .addr32_i(mem32_addr), .wdata32_i(mem32_wdata), .be32_i(mem32_be),
      .rvalid32_o(mem32_rvalid), .rready32_i(mem32_rready),
      .rdata32_o(mem32_rdata), .err32_o(mem32_err),
      // 64-bit ports (xbar R/W, loader, iDMA R/W).
      .req64_i(mem_init_req), .gnt64_o(mem_init_gnt), .we64_i(mem_init_we),
      .addr64_i(mem_init_addr), .wdata64_i(mem_init_wdata), .be64_i(mem_init_be),
      .rvalid64_o(mem_init_rvalid), .rready64_i(mem_axi_rready),
      .rdata64_o(mem_init_rdata), .err64_o(mem_init_err)
    );

    dmi_jtag #(
      .IdcodeValue(32'h0000_0001)
    ) i_dmi_jtag (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .testmode_i       (1'b0),
      // Synchronized DMI clear generated on TAP reset / dtmcs.dmihardreset;
      // wired to dm_top so a DMI recovery also flushes the DM-side response
      // queue (dm_csrs uses ~dmi_rst_ni as its response-FIFO flush).
      .dmi_rst_no       (dmi_rst_n),
      .dmi_req_o        (dmi_req),
      .dmi_req_valid_o  (dmi_req_valid),
      .dmi_req_ready_i  (dmi_req_ready),
      .dmi_resp_i       (dmi_resp),
      .dmi_resp_ready_o (dmi_resp_ready),
      .dmi_resp_valid_i (dmi_resp_valid),
      .tck_i            (jtag_tck_i),
      .tms_i            (jtag_tms_i),
      .trst_ni          (jtag_trst_ni),
      .td_i             (jtag_tdi_i),
      .td_o             (jtag_tdo_o),
      .tdo_oe_o         ()
    );

    dm_top #(
      .NrHarts         (1),
      .BusWidth        (64),
      // Non-zero selects the two-scratch debug ROM. The core-visible debug
      // window is still defined by DebugBaseAddr/DmHaltAddr/DmExceptionAddr.
      .DmBaseAddress   (DmRomBaseSelect),
      .SelectableHarts (1'b1)
    ) i_dm_top (
      .clk_i                (clk_i),
      .rst_ni               (rst_ni),
      .next_dm_addr_i       ('0),
      .testmode_i           (1'b0),
      .ndmreset_o           (ndmreset),
      .ndmreset_ack_i       (ndmreset_ack),
      .dmactive_o           (dmactive_o),
      .debug_req_o          ({debug_req_o}),
      .unavailable_i        ({core_debug_unavailable}),
      .hartinfo_i           ({HartInfo}),
      .slave_req_i          (dm_device_req),
      .slave_we_i           (dm_device_we),
      .slave_addr_i         (dm_device_addr),
      .slave_be_i           (dm_device_be),
      .slave_wdata_i        (dm_device_wdata),
      .slave_rdata_o        (dm_device_rdata),
      .master_req_o         (sba_req),
      .master_add_o         (sba_addr),
      .master_we_o          (sba_we),
      .master_wdata_o       (sba_wdata),
      .master_be_o          (sba_be),
      .master_gnt_i         (sba_gnt),
      .master_r_valid_i     (sba_r_valid),
      .master_r_err_i       (sba_r_err),
      .master_r_other_err_i (1'b0),
      .master_r_rdata_i     (sba_r_rdata),
      .dmi_rst_ni           (dmi_rst_n),
      .dmi_req_valid_i      (dmi_req_valid),
      .dmi_req_ready_o      (dmi_req_ready),
      .dmi_req_i            (dmi_req),
      .dmi_resp_valid_o     (dmi_resp_valid),
      .dmi_resp_ready_i     (dmi_resp_ready),
      .dmi_resp_o           (dmi_resp)
    );

    apb_uart_wrap #(
      .apb_req_t(soc_apb_req_t),
      .apb_rsp_t(soc_apb_resp_t)
    ) i_uart (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .apb_req_i (uart_apb_req),
      .apb_rsp_o (uart_apb_rsp),
      .intr_o    (uart_irq),
      .out1_no   (),
      .out2_no   (),
      .rts_no    (),
      .dtr_no    (),
      .cts_ni    (1'b0),
      .dsr_ni    (1'b0),
      .dcd_ni    (1'b0),
      .rin_ni    (1'b0),
      .sin_i     (uart_loader_active ? 1'b1 : uart_rx_i),
      .sout_o    (apb_uart_tx)
    );

    assign uart_tx_o = uart_loader_active ? uart_loader_tx : apb_uart_tx;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        clint_rtc_q <= 1'b0;
      end else begin
        clint_rtc_q <= ~clint_rtc_q;
      end
    end

    clint #(
      .reg_req_t (soc_reg_req_t),
      .reg_rsp_t (soc_reg_rsp_t)
    ) i_clint (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni),
      .testmode_i  (1'b0),
      .reg_req_i   (clint_reg_req),
      .reg_rsp_o   (clint_reg_rsp),
      .rtc_i       (clint_rtc_q),
      .timer_irq_o (clint_timer_irq),
      .ipi_o       (clint_ipi)
    );

    always_comb begin
      apb_rsp = '{default: '0};
      apb_rsp.pready = 1'b1;
      if (apb_req_i.psel && apb_req_i.penable) begin
        apb_rsp.pslverr = 1'b1;
      end
    end

    assign sba_r_ready = 1'b1;

    assign apb_rsp_o = apb_rsp;
  end
endmodule
