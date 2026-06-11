// SPDX-License-Identifier: Apache-2.0
//
// Testbench wrapper exposing soc_plic's register interface as flat ports for
// the cocotb regression (tb/test_plic.py). Four sources cover the priority
// ordering and tie-break cases.

module plic_dut (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        reg_valid_i,
  input  logic        reg_write_i,
  input  logic [23:0] reg_addr_i,
  input  logic [31:0] reg_wdata_i,
  input  logic [3:0]  reg_wstrb_i,
  output logic        reg_ready_o,
  output logic [31:0] reg_rdata_o,
  output logic        reg_error_o,

  input  logic [3:0]  irq_sources_i,
  output logic        irq_o
);
  import soc_bus_pkg::*;

  soc_reg_req_t reg_req;
  soc_reg_rsp_t reg_rsp;

  assign reg_req = '{
    addr:  reg_addr_i,
    write: reg_write_i,
    wdata: reg_wdata_i,
    wstrb: reg_wstrb_i,
    valid: reg_valid_i
  };

  assign reg_ready_o = reg_rsp.ready;
  assign reg_rdata_o = reg_rsp.rdata;
  assign reg_error_o = reg_rsp.error;

  soc_plic #(
    .NumSources (4)
  ) i_plic (
    .clk_i,
    .rst_ni,
    .reg_req_i     (reg_req),
    .reg_rsp_o     (reg_rsp),
    .irq_sources_i (irq_sources_i),
    .irq_o         (irq_o)
  );
endmodule
