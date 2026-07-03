// SPDX-License-Identifier: Apache-2.0
//
module corejack_cva6_axi_adapter #(
  parameter logic [63:0] BootAddr = 64'h0000_0000_8000_0000,
  parameter logic [63:0] HartId = 64'h0,
  parameter logic [63:0] DmBaseAddr = 64'h0,
  parameter logic [63:0] DmHaltAddr = 64'h800,
  parameter logic [63:0] DmExceptionAddr = 64'h810
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    debug_req_i,
  input  logic                    irq_software_i,
  input  logic                    irq_timer_i,
  input  logic                    irq_external_i,
  output soc_bus_pkg::soc_axi_req_t axi_req_o,
  input  soc_bus_pkg::soc_axi_resp_t axi_rsp_i,
  output logic                    alert_minor_o,
  output logic                    alert_major_internal_o,
  output logic                    alert_major_bus_o,
  output logic                    debug_unavailable_o,
  output logic                    core_sleep_o
);
  cva6 #(
    .noc_req_t  (soc_bus_pkg::soc_axi_req_t),
    .noc_resp_t (soc_bus_pkg::soc_axi_resp_t)
  ) i_cva6 (
    .clk_i,
    .rst_ni,
    .boot_addr_i  (BootAddr[cva6_config_pkg::CVA6ConfigXlen-1:0]),
    .hart_id_i    (HartId[cva6_config_pkg::CVA6ConfigXlen-1:0]),
    // irq_i[0] feeds mip.MEIP (machine external); irq_i[1] feeds the
    // supervisor external pending bit, which does not exist with RVS = 0.
    // The software IPI arrives through the dedicated ipi_i port.
    .irq_i        ({1'b0, irq_external_i}),
    .ipi_i        (irq_software_i),
    .time_irq_i   (irq_timer_i),
    .debug_req_i,
    .rvfi_probes_o(),
    .cvxif_req_o  (),
    .cvxif_resp_i ('0),
    .noc_req_o    (axi_req_o),
    .noc_resp_i   (axi_rsp_i)
  );

  assign alert_minor_o          = 1'b0;
  assign alert_major_internal_o = 1'b0;
  assign alert_major_bus_o      = 1'b0;
  assign debug_unavailable_o    = 1'b0;
  assign core_sleep_o           = 1'b0;

`ifndef SYNTHESIS
  initial begin
    if (DmBaseAddr != cva6_config_pkg::cva6_cfg.DmBaseAddress) begin
      $fatal(1, "CVA6 debug base address does not match cva6_corejack_config_pkg");
    end
    if ((DmHaltAddr - DmBaseAddr) != cva6_config_pkg::cva6_cfg.HaltAddress) begin
      $fatal(1, "CVA6 debug halt address does not match cva6_corejack_config_pkg");
    end
    if ((DmExceptionAddr - DmBaseAddr) != cva6_config_pkg::cva6_cfg.ExceptionAddress) begin
      $fatal(1, "CVA6 debug exception address does not match cva6_corejack_config_pkg");
    end
  end
`endif

  logic unused_debug_params;
  assign unused_debug_params = ^{DmBaseAddr, DmHaltAddr, DmExceptionAddr};
endmodule
