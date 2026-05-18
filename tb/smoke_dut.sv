module smoke_dut (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        apb_psel_i,
  input  logic        apb_penable_i,
  input  logic        apb_pwrite_i,
  input  logic [31:0] apb_paddr_i,
  input  logic [31:0] apb_pwdata_i,
  output logic [31:0] apb_prdata_o,
  output logic        apb_pready_o,
  output logic        apb_pslverr_o
);
  import soc_bus_pkg::*;

  soc_apb_req_t apb_req;
  soc_apb_resp_t apb_rsp;

  assign apb_req = '{
    paddr: apb_paddr_i,
    pprot: '0,
    psel: apb_psel_i,
    penable: apb_penable_i,
    pwrite: apb_pwrite_i,
    pwdata: apb_pwdata_i,
    pstrb: '1
  };

  soc_top #(
    .apb_req_t(soc_apb_req_t),
    .apb_rsp_t(soc_apb_resp_t),
    .axi_req_t(soc_axi_req_t),
    .axi_rsp_t(soc_axi_resp_t),
    .obi_req_t(soc_obi_req_t),
    .obi_rsp_t(soc_obi_rsp_t)
  ) i_soc_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .apb_req_i(apb_req),
    .apb_rsp_o(apb_rsp),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .jtag_tck_i(1'b0),
    .jtag_tms_i(1'b0),
    .jtag_trst_ni(1'b0),
    .jtag_tdi_i(1'b0),
    .jtag_tdo_o(),
    .dmactive_o(),
    .debug_req_o(),
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_sleep_o()
  );

  assign apb_prdata_o  = apb_rsp.prdata;
  assign apb_pready_o  = apb_rsp.pready;
  assign apb_pslverr_o = apb_rsp.pslverr;
endmodule
