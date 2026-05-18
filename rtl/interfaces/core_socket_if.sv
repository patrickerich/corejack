interface core_socket_if #(
  parameter int N_IRQ = 64,
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

  logic [N_IRQ-1:0] irq;
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
