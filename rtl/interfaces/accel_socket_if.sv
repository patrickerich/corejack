interface accel_socket_if #(
  parameter type mem_axi_req_t = logic,
  parameter type mem_axi_rsp_t = logic,
  parameter type csr_apb_req_t = logic,
  parameter type csr_apb_rsp_t = logic
);
  logic clk;
  logic rst_n;
  logic irq_o;

  logic power_en;
  logic isolate;
  logic retain;
  logic clk_en;

  mem_axi_req_t mem_req;
  mem_axi_rsp_t mem_rsp;

  csr_apb_req_t csr_req;
  csr_apb_rsp_t csr_rsp;
endinterface
