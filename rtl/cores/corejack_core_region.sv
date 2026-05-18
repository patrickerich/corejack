module corejack_core_region #(
  parameter int unsigned CoreType = platform_pkg::CORE_IBEX,
  parameter logic [31:0] BootAddr = 32'h8000_0000,
  parameter logic [31:0] HartId = 32'h0,
  parameter logic [31:0] DmBaseAddr = 32'h0000_0000,
  parameter logic [31:0] DmHaltAddr = 32'h0000_0800,
  parameter logic [31:0] DmExceptionAddr = 32'h0000_0810
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        debug_req_i,
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  input  logic [14:0] irq_fast_i,
  input  logic        irq_nm_i,

  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  output logic        alert_minor_o,
  output logic        alert_major_internal_o,
  output logic        alert_major_bus_o,
  output logic        debug_unavailable_o,
  output logic        core_sleep_o
);
  if (CoreType == platform_pkg::CORE_IBEX) begin : gen_ibex
    corejack_ibex_socket_adapter #(
      .BootAddr        (BootAddr),
      .HartId          (HartId),
      .DmBaseAddr      (DmBaseAddr),
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr)
    ) i_ibex_adapter (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
      .debug_req_i            (debug_req_i),
      .irq_software_i         (irq_software_i),
      .irq_timer_i            (irq_timer_i),
      .irq_external_i         (irq_external_i),
      .irq_fast_i             (irq_fast_i),
      .irq_nm_i               (irq_nm_i),
      .instr_req_o            (instr_req_o),
      .instr_gnt_i            (instr_gnt_i),
      .instr_rvalid_i         (instr_rvalid_i),
      .instr_addr_o           (instr_addr_o),
      .instr_rdata_i          (instr_rdata_i),
      .instr_err_i            (instr_err_i),
      .data_req_o             (data_req_o),
      .data_gnt_i             (data_gnt_i),
      .data_rvalid_i          (data_rvalid_i),
      .data_we_o              (data_we_o),
      .data_be_o              (data_be_o),
      .data_addr_o            (data_addr_o),
      .data_wdata_o           (data_wdata_o),
      .data_rdata_i           (data_rdata_i),
      .data_err_i             (data_err_i),
      .alert_minor_o          (alert_minor_o),
      .alert_major_internal_o (alert_major_internal_o),
      .alert_major_bus_o      (alert_major_bus_o),
      .core_sleep_o           (core_sleep_o)
    );

    assign debug_unavailable_o = 1'b0;
  end else if (CoreType == platform_pkg::CORE_CV32E40P) begin : gen_cv32e40p
    localparam logic [31:0] Cv32e40pBootAddr = BootAddr + 32'h80;

    corejack_cv32e40p_socket_adapter #(
      .BootAddr        (Cv32e40pBootAddr),
      .MtvecAddr       (BootAddr),
      .HartId          (HartId),
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr)
    ) i_cv32e40p_adapter (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
      .debug_req_i            (debug_req_i),
      .irq_software_i         (irq_software_i),
      .irq_timer_i            (irq_timer_i),
      .irq_external_i         (irq_external_i),
      .irq_fast_i             (irq_fast_i),
      .irq_nm_i               (irq_nm_i),
      .instr_req_o            (instr_req_o),
      .instr_gnt_i            (instr_gnt_i),
      .instr_rvalid_i         (instr_rvalid_i),
      .instr_addr_o           (instr_addr_o),
      .instr_rdata_i          (instr_rdata_i),
      .instr_err_i            (instr_err_i),
      .data_req_o             (data_req_o),
      .data_gnt_i             (data_gnt_i),
      .data_rvalid_i          (data_rvalid_i),
      .data_we_o              (data_we_o),
      .data_be_o              (data_be_o),
      .data_addr_o            (data_addr_o),
      .data_wdata_o           (data_wdata_o),
      .data_rdata_i           (data_rdata_i),
      .data_err_i             (data_err_i),
      .alert_minor_o          (alert_minor_o),
      .alert_major_internal_o (alert_major_internal_o),
      .alert_major_bus_o      (alert_major_bus_o),
      .core_sleep_o           (core_sleep_o)
    );

    assign debug_unavailable_o = 1'b0;
  end else if (CoreType == platform_pkg::CORE_CV32E40X) begin : gen_cv32e40x
    localparam logic [31:0] Cv32e40xBootAddr = BootAddr + 32'h80;

    corejack_cv32e40x_socket_adapter #(
      .BootAddr        (Cv32e40xBootAddr),
      .MtvecAddr       (BootAddr),
      .HartId          (HartId),
      .DmBaseAddr      (DmBaseAddr),
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr)
    ) i_cv32e40x_adapter (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
      .debug_req_i            (debug_req_i),
      .irq_software_i         (irq_software_i),
      .irq_timer_i            (irq_timer_i),
      .irq_external_i         (irq_external_i),
      .irq_fast_i             (irq_fast_i),
      .irq_nm_i               (irq_nm_i),
      .instr_req_o            (instr_req_o),
      .instr_gnt_i            (instr_gnt_i),
      .instr_rvalid_i         (instr_rvalid_i),
      .instr_addr_o           (instr_addr_o),
      .instr_rdata_i          (instr_rdata_i),
      .instr_err_i            (instr_err_i),
      .data_req_o             (data_req_o),
      .data_gnt_i             (data_gnt_i),
      .data_rvalid_i          (data_rvalid_i),
      .data_we_o              (data_we_o),
      .data_be_o              (data_be_o),
      .data_addr_o            (data_addr_o),
      .data_wdata_o           (data_wdata_o),
      .data_rdata_i           (data_rdata_i),
      .data_err_i             (data_err_i),
      .alert_minor_o          (alert_minor_o),
      .alert_major_internal_o (alert_major_internal_o),
      .alert_major_bus_o      (alert_major_bus_o),
      .core_sleep_o           (core_sleep_o)
    );

    assign debug_unavailable_o = 1'b0;
  end else if (CoreType == platform_pkg::CORE_CV32E40S) begin : gen_cv32e40s
    corejack_cv32e40s_socket_adapter #(
      .BootAddr        (BootAddr),
      .MtvecAddr       (BootAddr),
      .HartId          (HartId),
      .DmBaseAddr      (DmBaseAddr),
      .DmHaltAddr      (DmHaltAddr),
      .DmExceptionAddr (DmExceptionAddr)
    ) i_cv32e40s_adapter (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
      .debug_req_i            (debug_req_i),
      .irq_software_i         (irq_software_i),
      .irq_timer_i            (irq_timer_i),
      .irq_external_i         (irq_external_i),
      .irq_fast_i             (irq_fast_i),
      .irq_nm_i               (irq_nm_i),
      .instr_req_o            (instr_req_o),
      .instr_gnt_i            (instr_gnt_i),
      .instr_rvalid_i         (instr_rvalid_i),
      .instr_addr_o           (instr_addr_o),
      .instr_rdata_i          (instr_rdata_i),
      .instr_err_i            (instr_err_i),
      .data_req_o             (data_req_o),
      .data_gnt_i             (data_gnt_i),
      .data_rvalid_i          (data_rvalid_i),
      .data_we_o              (data_we_o),
      .data_be_o              (data_be_o),
      .data_addr_o            (data_addr_o),
      .data_wdata_o           (data_wdata_o),
      .data_rdata_i           (data_rdata_i),
      .data_err_i             (data_err_i),
      .alert_minor_o          (alert_minor_o),
      .alert_major_internal_o (alert_major_internal_o),
      .alert_major_bus_o      (alert_major_bus_o),
      .debug_unavailable_o    (debug_unavailable_o),
      .core_sleep_o           (core_sleep_o)
    );
  end else if (CoreType == platform_pkg::CORE_CVA6) begin : gen_cva6_requires_axi
    assign instr_req_o            = 1'b0;
    assign instr_addr_o           = '0;
    assign data_req_o             = 1'b0;
    assign data_we_o              = 1'b0;
    assign data_be_o              = '0;
    assign data_addr_o            = '0;
    assign data_wdata_o           = '0;
    assign alert_minor_o          = 1'b0;
    assign alert_major_internal_o = 1'b1;
    assign alert_major_bus_o      = 1'b0;
    assign debug_unavailable_o    = 1'b1;
    assign core_sleep_o           = 1'b1;

`ifndef SYNTHESIS
    initial begin
      $fatal(1, "CVA6 requires a native AXI core path; the split OBI core region is RV32-only");
    end
`endif
  end else if (CoreType == platform_pkg::CORE_SERV) begin : gen_serv
    corejack_serv_socket_adapter #(
      .BootAddr (BootAddr + 32'h80)
    ) i_serv_adapter (
      .clk_i,
      .rst_ni,
      .irq_timer_i  (irq_timer_i),
      .instr_req_o,
      .instr_gnt_i,
      .instr_rvalid_i,
      .instr_addr_o,
      .instr_rdata_i,
      .instr_err_i,
      .data_req_o,
      .data_gnt_i,
      .data_rvalid_i,
      .data_we_o,
      .data_be_o,
      .data_addr_o,
      .data_wdata_o,
      .data_rdata_i,
      .data_err_i,
      .core_sleep_o
    );

    assign alert_minor_o          = 1'b0;
    assign alert_major_internal_o = 1'b0;
    assign alert_major_bus_o      = 1'b0;
    assign debug_unavailable_o    = 1'b1;
  end else if (CoreType == platform_pkg::CORE_PICORV32) begin : gen_picorv32
    corejack_picorv32_socket_adapter #(
      .BootAddr (BootAddr + 32'h80)
    ) i_picorv32_adapter (
      .clk_i,
      .rst_ni,
      .instr_req_o,
      .instr_gnt_i,
      .instr_rvalid_i,
      .instr_addr_o,
      .instr_rdata_i,
      .instr_err_i,
      .data_req_o,
      .data_gnt_i,
      .data_rvalid_i,
      .data_we_o,
      .data_be_o,
      .data_addr_o,
      .data_wdata_o,
      .data_rdata_i,
      .data_err_i,
      .core_sleep_o
    );

    assign alert_minor_o          = 1'b0;
    assign alert_major_internal_o = 1'b0;
    assign alert_major_bus_o      = 1'b0;
    assign debug_unavailable_o    = 1'b1;
  end else if (CoreType == platform_pkg::CORE_CVW) begin : gen_cvw
    corejack_cvw_ahb_adapter i_cvw_adapter (
      .clk_i,
      .rst_ni,
      .irq_software_i,
      .irq_timer_i,
      .irq_external_i,
      .instr_req_o,
      .instr_gnt_i,
      .instr_rvalid_i,
      .instr_addr_o,
      .instr_rdata_i,
      .instr_err_i,
      .data_req_o,
      .data_gnt_i,
      .data_rvalid_i,
      .data_we_o,
      .data_be_o,
      .data_addr_o,
      .data_wdata_o,
      .data_rdata_i,
      .data_err_i,
      .core_sleep_o
    );

    assign alert_minor_o          = 1'b0;
    assign alert_major_internal_o = 1'b0;
    assign alert_major_bus_o      = 1'b0;
    assign debug_unavailable_o    = 1'b1;
  end else begin : gen_unsupported
    assign instr_req_o            = 1'b0;
    assign instr_addr_o           = '0;
    assign data_req_o             = 1'b0;
    assign data_we_o              = 1'b0;
    assign data_be_o              = '0;
    assign data_addr_o            = '0;
    assign data_wdata_o           = '0;
    assign alert_minor_o          = 1'b0;
    assign alert_major_internal_o = 1'b1;
    assign alert_major_bus_o      = 1'b0;
    assign debug_unavailable_o    = 1'b1;
    assign core_sleep_o           = 1'b1;

`ifndef SYNTHESIS
    initial begin
      $fatal(1, "Unsupported CoreJack CoreType %0d", CoreType);
    end
`endif
  end
endmodule
