// SPDX-License-Identifier: Apache-2.0
//
module corejack_cv32e40p_socket_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0000,
  parameter logic [31:0] MtvecAddr = 32'h8000_0000,
  parameter logic [31:0] HartId = 32'h0,
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
  output logic        core_sleep_o
);
  logic [31:0] irq;
  logic        irq_ack_unused;
  logic [4:0]  irq_id_unused;
  logic        debug_havereset_unused;
  logic        debug_running_unused;
  logic        debug_halted_unused;
  logic        unused_bus_err;
  logic        unused_irq_nm;

  always_comb begin
    irq       = '0;
    irq[3]    = irq_software_i;
    irq[7]    = irq_timer_i;
    irq[11]   = irq_external_i;
    irq[30:16] = irq_fast_i;
  end

  assign alert_minor_o          = 1'b0;
  assign alert_major_internal_o = 1'b0;
  assign alert_major_bus_o      = 1'b0;
  assign unused_bus_err         = instr_err_i ^ data_err_i;
  assign unused_irq_nm          = irq_nm_i;

`ifndef SYNTHESIS
  // cv32e40p_top has no bus-error inputs, so error responses are necessarily
  // dropped; fail loudly in simulation (same policy as the SERV and PicoRV32
  // adapters) instead of letting the core continue on error/garbage data.
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (instr_err_i && instr_rvalid_i) begin
        $fatal(1, "CV32E40P instruction bus error is not supported");
      end

      if (data_err_i && data_rvalid_i) begin
        $fatal(1, "CV32E40P data bus error is not supported");
      end
    end
  end
`endif

  cv32e40p_top #(
    .COREV_PULP       (0),
    .COREV_CLUSTER    (0),
    .FPU              (0),
    .FPU_ADDMUL_LAT   (0),
    .FPU_OTHERS_LAT   (0),
    .ZFINX            (0),
    .NUM_MHPMCOUNTERS (1)
  ) i_cv32e40p (
    .clk_i               (clk_i),
    .rst_ni              (rst_ni),
    .pulp_clock_en_i     (1'b1),
    .scan_cg_en_i        (1'b0),
    .boot_addr_i         (BootAddr),
    .mtvec_addr_i        (MtvecAddr),
    .dm_halt_addr_i      (DmHaltAddr),
    .hart_id_i           (HartId),
    .dm_exception_addr_i (DmExceptionAddr),
    .instr_req_o         (instr_req_o),
    .instr_gnt_i         (instr_gnt_i),
    .instr_rvalid_i      (instr_rvalid_i),
    .instr_addr_o        (instr_addr_o),
    .instr_rdata_i       (instr_rdata_i),
    .data_req_o          (data_req_o),
    .data_gnt_i          (data_gnt_i),
    .data_rvalid_i       (data_rvalid_i),
    .data_we_o           (data_we_o),
    .data_be_o           (data_be_o),
    .data_addr_o         (data_addr_o),
    .data_wdata_o        (data_wdata_o),
    .data_rdata_i        (data_rdata_i),
    .irq_i               (irq),
    .irq_ack_o           (irq_ack_unused),
    .irq_id_o            (irq_id_unused),
    .debug_req_i         (debug_req_i),
    .debug_havereset_o   (debug_havereset_unused),
    .debug_running_o     (debug_running_unused),
    .debug_halted_o      (debug_halted_unused),
    .fetch_enable_i      (1'b1),
    .core_sleep_o        (core_sleep_o)
  );
endmodule
