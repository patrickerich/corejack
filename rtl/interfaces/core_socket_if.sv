// SPDX-License-Identifier: Apache-2.0
//
// ASPIRATIONAL - NOT YET WIRED IN. This interface sketches a future bundled
// core socket; the implemented socket is the flat split instruction/data OBI
// port list of corejack_core_region plus per-line IRQs. Keep in sync with (or
// fold into) the real contract before first use.
interface core_socket_if #(
  parameter int unsigned NumIrq = 64,
  parameter type instr_axi_req_t = logic,
  parameter type instr_axi_rsp_t = logic,
  parameter type data_axi_req_t = logic,
  parameter type data_axi_rsp_t = logic,
  parameter type obi_req_t = logic,
  parameter type obi_rsp_t = logic,
  parameter type hartinfo_t = logic
);
  logic clk;
  logic rst_n;

  logic [NumIrq-1:0] irq;
  logic debug_req;
  hartinfo_t hart_info;

  logic power_en;
  logic isolate;
  logic retain;
  logic clk_en;

  instr_axi_req_t instr_req;
  instr_axi_rsp_t instr_rsp;

  data_axi_req_t data_req;
  data_axi_rsp_t data_rsp;

  obi_req_t obi_req;
  obi_rsp_t obi_rsp;
endinterface
