module soc_top #(
  parameter int N_IRQ = 64,
  parameter int unsigned CoreType = platform_pkg::CORE_IBEX,
  parameter type apb_req_t = soc_bus_pkg::soc_apb_req_t,
  parameter type apb_rsp_t = soc_bus_pkg::soc_apb_resp_t,
  parameter type axi_req_t = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_rsp_t = soc_bus_pkg::soc_axi_resp_t,
  parameter type obi_req_t = soc_bus_pkg::soc_obi_req_t,
  parameter type obi_rsp_t = soc_bus_pkg::soc_obi_rsp_t,
  parameter bit EnablePlatform = 1'b0,
  parameter logic [31:0] DebugBaseAddr = 32'h0000_0000,
  parameter logic [31:0] ClintBaseAddr = 32'h0200_0000,
  parameter logic [31:0] UartBaseAddr = 32'h1000_0000,
  parameter logic [31:0] RamBaseAddr = 32'h8000_0000,
  parameter int unsigned RamWords = 262144,
  parameter bit EnableUartLoader = 1'b0,
  parameter int unsigned UartLoaderClockHz = 25_000_000,
  parameter int unsigned UartLoaderBaud = 115_200,
  parameter string MemInitFile = "",
  parameter string MemInitPath = "",
  parameter mem_ss_pkg::mem_impl_e MemImpl = mem_ss_pkg::MemImplModel
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
  import addr_map_pkg::*;
  import soc_bus_pkg::*;
  import dm::*;
  import mem_ss_pkg::*;

  if (!EnablePlatform) begin : gen_stub
    logic [31:0] accel_cfg_reg_q;
    logic [31:0] debug_status_q;
    logic        apb_hit_uart;
    logic        apb_hit_debug;
    logic        apb_access;
    apb_rsp_t    apb_rsp;

    assign apb_hit_uart  = (apb_req_i.paddr - UART0_BASE) < UART0_SIZE;
    assign apb_hit_debug = (apb_req_i.paddr - DEBUG0_BASE) < DEBUG0_SIZE;
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
    localparam int unsigned MemInitPorts = 2;
    localparam int unsigned CoreAxiPorts = 3;
    localparam int unsigned FabricAxiPorts = 4;
    localparam int unsigned MemDataWidth = 64;
    localparam int unsigned MemNumBanks = 4;
    localparam int unsigned MemBytesPerWord = MemDataWidth / 8;
    localparam int unsigned MemWords = RamWords / 2;
    localparam int unsigned MemTagWidth = 1;
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
    logic ndmreset_q;
    logic core_debug_unavailable;
    logic uart_loader_active;
    logic uart_loader_tx;
    logic apb_uart_tx;
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
    logic [MemInitPorts-1:0][MemTagWidth-1:0]     mem_init_tag;
    logic [MemInitPorts-1:0]                      mem_init_gnt;
    logic [MemInitPorts-1:0]                      mem_init_rvalid;
    logic [MemInitPorts-1:0][MemDataWidth-1:0]    mem_init_rdata;
    logic [MemInitPorts-1:0]                      mem_init_err;
    logic [MemInitPorts-1:0][MemTagWidth-1:0]     mem_init_rtag;
    logic [MemInitPorts-1:0]                      mem_axi_rready;
    soc_axi_req_t [CoreAxiPorts-1:0]              core_axi_req;
    soc_axi_resp_t [CoreAxiPorts-1:0]             core_axi_rsp;
    soc_axi_req_t                                 instr_axi_req;
    soc_axi_resp_t                                instr_axi_rsp;
    soc_axi_req_t                                 data_axi_req;
    soc_axi_resp_t                                data_axi_rsp;
    soc_axi_req_t                                 cva6_axi_req;
    soc_axi_resp_t                                cva6_axi_rsp;
    soc_axi_req_t                                 fabric_axi_req;
    soc_axi_resp_t                                fabric_axi_rsp;
    soc_axi_req_t [FabricAxiPorts-1:0]            target_axi_req;
    soc_axi_resp_t [FabricAxiPorts-1:0]           target_axi_rsp;
    axi_pkg::xbar_rule_32_t [FabricAxiPorts-1:0]  fabric_addr_map;

    soc_apb_req_t  uart_apb_req;
    soc_apb_resp_t uart_apb_rsp;
    soc_reg_req_t  clint_reg_req;
    soc_reg_rsp_t  clint_reg_rsp;
    apb_rsp_t      apb_rsp;
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

    soc_axi_protocol_checker i_fabric_axi_checker (
      .clk_i,
      .rst_ni,
      .req_i (fabric_axi_req),
      .rsp_i (fabric_axi_rsp)
    );

    for (genvar i = 0; i < FabricAxiPorts; i++) begin : gen_target_axi_checkers
      soc_axi_protocol_checker i_axi_checker (
        .clk_i,
        .rst_ni,
        .req_i (target_axi_req[i]),
        .rsp_i (target_axi_rsp[i])
      );
    end

    initial begin : validate_mem_geometry
      if ((RamWords % 2) != 0) begin
        $fatal(1, "soc_top: RamWords must be even for the 64-bit SRAM path");
      end
      if ((MemWords % MemNumBanks) != 0) begin
        $fatal(1, "soc_top: 64-bit SRAM word count must divide evenly across banks");
      end
    end
`endif

    rstgen i_rstgen_core (
      .clk_i       (clk_i),
      .rst_ni      (rst_ni & ~ndmreset & ~uart_loader_active),
      .test_mode_i (1'b0),
      .rst_no      (core_rst_ni),
      .init_no     (core_init_ni)
    );

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        core_init_ni_q <= 1'b0;
        ndmreset_q     <= 1'b0;
        ndmreset_ack   <= 1'b0;
      end else begin
        core_init_ni_q <= core_init_ni;
        ndmreset_q     <= ndmreset;
        ndmreset_ack   <= ndmreset_q && core_init_ni && !core_init_ni_q;
      end
    end

    assign mem_init_tag = '0;
    assign fabric_addr_map = '{
      '{idx: 0, start_addr: RamBaseAddr,   end_addr: RamBaseAddr + RamSize},
      '{idx: 1, start_addr: UartBaseAddr,  end_addr: UartBaseAddr + UartSize},
      '{idx: 2, start_addr: DebugBaseAddr, end_addr: DebugBaseAddr + DebugSize},
      '{idx: 3, start_addr: ClintBaseAddr, end_addr: ClintBaseAddr + ClintSize}
    };

    if (CoreType == platform_pkg::CORE_CVA6) begin : gen_cva6_core_path
      assign core_axi_req[0] = cva6_axi_req;
      assign core_axi_req[1] = '0;
      assign instr_axi_rsp   = '0;
      assign data_axi_rsp    = '0;
      assign cva6_axi_rsp    = core_axi_rsp[0];

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
        .irq_external_i         (uart_irq),
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
        .irq_external_i         (uart_irq),
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

    soc_obi_to_axi i_instr_obi_to_axi (
      .clk_i,
      .rst_ni,
      .s_addr_i    (instr_addr),
      .s_wdata_i   ('0),
      .s_be_i      (4'hF),
      .s_we_i      (1'b0),
      .s_req_i     (instr_req),
      .s_gnt_o     (instr_gnt),
      .s_rvalid_o  (instr_rvalid),
      .s_rready_i  (instr_rready),
      .s_rdata_o   (instr_rdata),
      .s_err_o     (instr_err),
      .m_axi_req_o (instr_axi_req),
      .m_axi_rsp_i (instr_axi_rsp)
    );

    soc_obi_to_axi i_data_obi_to_axi (
      .clk_i,
      .rst_ni,
      .s_addr_i    (data_addr),
      .s_wdata_i   (data_wdata),
      .s_be_i      (data_be),
      .s_we_i      (data_we),
      .s_req_i     (data_req),
      .s_gnt_o     (data_gnt),
      .s_rvalid_o  (data_rvalid),
      .s_rready_i  (data_rready),
      .s_rdata_o   (data_rdata),
      .s_err_o     (data_err),
      .m_axi_req_o (data_axi_req),
      .m_axi_rsp_i (data_axi_rsp)
    );

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

    soc_axi_arbiter #(
      .NumSlvPorts (CoreAxiPorts)
    ) i_core_axi_arbiter (
      .clk_i,
      .rst_ni,
      .slv_reqs_i  (core_axi_req),
      .slv_resps_o (core_axi_rsp),
      .mst_req_o   (fabric_axi_req),
      .mst_resp_i  (fabric_axi_rsp)
    );

    soc_axi_demux #(
      .NumMstPorts (FabricAxiPorts),
      .NoAddrRules (FabricAxiPorts),
      .rule_t      (axi_pkg::xbar_rule_32_t)
    ) i_fabric_axi_demux (
      .clk_i,
      .rst_ni,
      .slv_req_i   (fabric_axi_req),
      .slv_resp_o  (fabric_axi_rsp),
      .mst_reqs_o  (target_axi_req),
      .mst_resps_i (target_axi_rsp),
      .addr_map_i  (fabric_addr_map)
    );

    soc_axi_to_mem #(
      .AddrWidth (32),
      .DataWidth (MemDataWidth)
    ) i_axi_to_mem (
      .clk_i,
      .rst_ni,
      .s_axi_req_i  (target_axi_req[0]),
      .s_axi_rsp_o  (target_axi_rsp[0]),
      .mem_req_o    (mem_init_req[0]),
      .mem_we_o     (mem_init_we[0]),
      .mem_addr_o   (mem_init_addr[0]),
      .mem_wdata_o  (mem_init_wdata[0]),
      .mem_be_o     (mem_init_be[0]),
      .mem_gnt_i    (mem_init_gnt[0]),
      .mem_rvalid_i (mem_init_rvalid[0]),
      .mem_rready_o (mem_axi_rready[0]),
      .mem_rdata_i  (mem_init_rdata[0]),
      .mem_err_i    (mem_init_err[0])
    );

    if (EnableUartLoader) begin : gen_uart_sram_loader
      logic uart_loader_done;

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
        .done_o        (uart_loader_done),
        .mem_req_o     (mem_init_req[1]),
        .mem_we_o      (mem_init_we[1]),
        .mem_addr_o    (mem_init_addr[1]),
        .mem_wdata_o   (mem_init_wdata[1]),
        .mem_be_o      (mem_init_be[1]),
        .mem_gnt_i     (mem_init_gnt[1]),
        .mem_rvalid_i  (mem_init_rvalid[1]),
        .mem_rready_o  (mem_axi_rready[1]),
        .mem_err_i     (mem_init_err[1])
      );
    end else begin : gen_no_uart_sram_loader
      assign uart_loader_active = 1'b0;
      assign uart_loader_tx     = 1'b1;
      assign mem_init_req[1]    = 1'b0;
      assign mem_init_we[1]     = 1'b0;
      assign mem_init_addr[1]   = '0;
      assign mem_init_wdata[1]  = '0;
      assign mem_init_be[1]     = '0;
      assign mem_axi_rready[1]  = 1'b1;
    end

    soc_axi_to_apb #(
      .BaseAddr (UartBaseAddr)
    ) i_axi_to_uart_apb (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[1]),
      .s_axi_rsp_o (target_axi_rsp[1]),
      .m_apb_req_o (uart_apb_req),
      .m_apb_rsp_i (uart_apb_rsp)
    );

    soc_axi_to_dm #(
      .BaseAddr (DebugBaseAddr)
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
      .BaseAddr (ClintBaseAddr)
    ) i_axi_to_clint_reg (
      .clk_i,
      .rst_ni,
      .s_axi_req_i (target_axi_req[3]),
      .s_axi_rsp_o (target_axi_rsp[3]),
      .m_reg_req_o (clint_reg_req),
      .m_reg_rsp_i (clint_reg_rsp)
    );

    soc_mem_ss #(
      .AddrWidth(32),
      .DataWidth(MemDataWidth),
      .NumInitPorts(MemInitPorts),
      .InitTagWidth(MemTagWidth),
      .NumBanks(MemNumBanks),
      .NumWordsPerBank(MemWords / MemNumBanks),
      .BaseAddr(RamBaseAddr),
      .AddressShift($clog2(MemBytesPerWord)),
      .MemInitPath((MemInitPath != "") ? MemInitPath : MemInitFile),
      .MemImpl(MemImpl)
    ) i_mem_ss (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .init_req_i(mem_init_req),
      .init_we_i(mem_init_we),
      .init_addr_i(mem_init_addr),
      .init_wdata_i(mem_init_wdata),
      .init_be_i(mem_init_be),
      .init_tag_i(mem_init_tag),
      .init_gnt_o(mem_init_gnt),
      .init_rvalid_o(mem_init_rvalid),
      .init_rready_i(mem_axi_rready),
      .init_rdata_o(mem_init_rdata),
      .init_err_o(mem_init_err),
      .init_rtag_o(mem_init_rtag)
    );

    dmi_jtag #(
      .IdcodeValue(32'h0000_0001)
    ) i_dmi_jtag (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .testmode_i       (1'b0),
      .dmi_rst_no       (),
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
      .dmi_rst_ni           (rst_ni),
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
