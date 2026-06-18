module axi_adapter_dut
  import soc_bus_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,

  input  logic        obi_req_i,
  input  logic        obi_we_i,
  input  logic [31:0] obi_addr_i,
  input  logic [31:0] obi_wdata_i,
  input  logic [3:0]  obi_be_i,
  output logic        obi_gnt_o,
  output logic        obi_rvalid_o,
  input  logic        obi_rready_i,
  output logic [31:0] obi_rdata_o,
  output logic        obi_err_o,

  input  logic        obi1_req_i,
  input  logic        obi1_we_i,
  input  logic [31:0] obi1_addr_i,
  input  logic [31:0] obi1_wdata_i,
  input  logic [3:0]  obi1_be_i,
  output logic        obi1_gnt_o,
  output logic        obi1_rvalid_o,
  input  logic        obi1_rready_i,
  output logic [31:0] obi1_rdata_o,
  output logic        obi1_err_o,

  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic [31:0] mem_addr_o,
  output logic [63:0] mem_wdata_o,
  output logic [7:0]  mem_be_o,
  input  logic        mem_gnt_i,
  input  logic        mem_rvalid_i,
  output logic        mem_rready_o,
  input  logic [63:0] mem_rdata_i,
  input  logic        mem_err_i,

  output logic        apb_psel_o,
  output logic        apb_penable_o,
  output logic        apb_pwrite_o,
  output logic [31:0] apb_paddr_o,
  output logic [31:0] apb_pwdata_o,
  output logic [3:0]  apb_pstrb_o,
  input  logic        apb_pready_i,
  input  logic [31:0] apb_prdata_i,
  input  logic        apb_pslverr_i,

  output logic        dm_req_o,
  output logic        dm_we_o,
  output logic [63:0] dm_addr_o,
  output logic [7:0]  dm_be_o,
  output logic [63:0] dm_wdata_o,
  input  logic [63:0] dm_rdata_i
);
  localparam logic [31:0] RamBaseAddr   = 32'h8000_0000;
  localparam logic [31:0] RamSize       = 32'h0010_0000;
  localparam logic [31:0] UartBaseAddr  = 32'h1000_0000;
  localparam logic [31:0] UartSize      = 32'h0000_1000;
  localparam logic [31:0] DebugBaseAddr = 32'h0000_0000;
  localparam logic [31:0] DebugSize     = 32'h0000_1000;

  // Two OBI initiators drive crossbar slave ports 0/1; a third slave port is
  // tied off so the crossbar master-side ID width matches the platform soc_top
  // (NoSlvPorts=3 -> +$clog2(3) ID bits -> the soc_axi_mst_* types).
  localparam int unsigned NumSlv = 3;
  localparam int unsigned NumMst = 3;

  soc_axi_req_t  [NumSlv-1:0]  axi_slv_req;
  soc_axi_resp_t [NumSlv-1:0]  axi_slv_rsp;
  soc_axi_mst_req_t  [NumMst-1:0]  target_axi_req;
  soc_axi_mst_resp_t [NumMst-1:0]  target_axi_rsp;
  axi_pkg::xbar_rule_64_t [NumMst-1:0] addr_map;
  soc_apb_req_t        apb_req;
  soc_apb_resp_t       apb_rsp;

  localparam axi_pkg::xbar_cfg_t DutXbarCfg = '{
    NoSlvPorts:         NumSlv,
    NoMstPorts:         NumMst,
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
    NoAddrRules:        NumMst
  };

  // Slave port 2 is unused in this harness.
  assign axi_slv_req[2] = '0;

  for (genvar i = 0; i < 2; i++) begin : gen_slv_axi_checkers
    soc_axi_protocol_checker i_axi_checker (
      .clk_i,
      .rst_ni,
      .req_i (axi_slv_req[i]),
      .rsp_i (axi_slv_rsp[i])
    );
  end

  for (genvar i = 0; i < NumMst; i++) begin : gen_target_axi_checkers
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

  assign addr_map = '{
    '{idx: 0, start_addr: RamBaseAddr,   end_addr: RamBaseAddr + RamSize},
    '{idx: 1, start_addr: UartBaseAddr,  end_addr: UartBaseAddr + UartSize},
    '{idx: 2, start_addr: DebugBaseAddr, end_addr: DebugBaseAddr + DebugSize}
  };

  assign apb_rsp = '{
    pready:  apb_pready_i,
    prdata:  apb_prdata_i,
    pslverr: apb_pslverr_i
  };

  assign apb_psel_o    = apb_req.psel;
  assign apb_penable_o = apb_req.penable;
  assign apb_pwrite_o  = apb_req.pwrite;
  assign apb_paddr_o   = apb_req.paddr;
  assign apb_pwdata_o  = apb_req.pwdata;
  assign apb_pstrb_o   = apb_req.pstrb;

  soc_obi_to_axi i_obi_to_axi (
    .clk_i,
    .rst_ni,
    .s_addr_i     (obi_addr_i),
    .s_wdata_i    (obi_wdata_i),
    .s_be_i       (obi_be_i),
    .s_we_i       (obi_we_i),
    .s_req_i      (obi_req_i),
    .s_gnt_o      (obi_gnt_o),
    .s_rvalid_o   (obi_rvalid_o),
    .s_rready_i   (obi_rready_i),
    .s_rdata_o    (obi_rdata_o),
    .s_err_o      (obi_err_o),
    .m_axi_req_o  (axi_slv_req[0]),
    .m_axi_rsp_i  (axi_slv_rsp[0])
  );

  soc_obi_to_axi i_obi1_to_axi (
    .clk_i,
    .rst_ni,
    .s_addr_i     (obi1_addr_i),
    .s_wdata_i    (obi1_wdata_i),
    .s_be_i       (obi1_be_i),
    .s_we_i       (obi1_we_i),
    .s_req_i      (obi1_req_i),
    .s_gnt_o      (obi1_gnt_o),
    .s_rvalid_o   (obi1_rvalid_o),
    .s_rready_i   (obi1_rready_i),
    .s_rdata_o    (obi1_rdata_o),
    .s_err_o      (obi1_err_o),
    .m_axi_req_o  (axi_slv_req[1]),
    .m_axi_rsp_i  (axi_slv_rsp[1])
  );

  axi_xbar #(
    .Cfg           (DutXbarCfg),
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
  ) i_axi_xbar (
    .clk_i,
    .rst_ni,
    .test_i                (1'b0),
    .slv_ports_req_i       (axi_slv_req),
    .slv_ports_resp_o      (axi_slv_rsp),
    .mst_ports_req_o       (target_axi_req),
    .mst_ports_resp_i      (target_axi_rsp),
    .addr_map_i            (addr_map),
    .en_default_mst_port_i ('0),
    .default_mst_port_i    ('0)
  );

  // The dual-engine soc_axi_to_mem drives two independent init ports (read +
  // write). This unit harness exercises one direction at a time, so the two
  // ports are merged onto the single external mem_* stimulus port; concurrent
  // two-port behaviour is covered by the full SoC sim, not here.
  logic        mem_rd_req, mem_rd_we, mem_rd_rready;
  logic [31:0] mem_rd_addr;
  logic [63:0] mem_rd_wdata;
  logic [7:0]  mem_rd_be;
  logic        mem_wr_req, mem_wr_we, mem_wr_rready;
  logic [31:0] mem_wr_addr;
  logic [63:0] mem_wr_wdata;
  logic [7:0]  mem_wr_be;

  soc_axi_to_mem #(
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
    .mem_rd_req_o    (mem_rd_req),
    .mem_rd_we_o     (mem_rd_we),
    .mem_rd_addr_o   (mem_rd_addr),
    .mem_rd_wdata_o  (mem_rd_wdata),
    .mem_rd_be_o     (mem_rd_be),
    .mem_rd_gnt_i    (mem_gnt_i),
    .mem_rd_rvalid_i (mem_rvalid_i),
    .mem_rd_rready_o (mem_rd_rready),
    .mem_rd_rdata_i  (mem_rdata_i),
    .mem_rd_err_i    (mem_err_i),
    .mem_wr_req_o    (mem_wr_req),
    .mem_wr_we_o     (mem_wr_we),
    .mem_wr_addr_o   (mem_wr_addr),
    .mem_wr_wdata_o  (mem_wr_wdata),
    .mem_wr_be_o     (mem_wr_be),
    .mem_wr_gnt_i    (mem_gnt_i),
    .mem_wr_rvalid_i (mem_rvalid_i),
    .mem_wr_rready_o (mem_wr_rready),
    .mem_wr_err_i    (mem_err_i)
  );

  assign mem_req_o    = mem_rd_req | mem_wr_req;
  assign mem_we_o     = mem_wr_req;
  assign mem_addr_o   = mem_wr_req ? mem_wr_addr : mem_rd_addr;
  assign mem_wdata_o  = mem_wr_wdata;
  assign mem_be_o     = mem_wr_req ? mem_wr_be : mem_rd_be;
  assign mem_rready_o = mem_rd_rready | mem_wr_rready;

  soc_axi_to_apb #(
    .BaseAddr      (UartBaseAddr),
    .axi_req_t     (soc_axi_mst_req_t),
    .axi_resp_t    (soc_axi_mst_resp_t),
    .axi_aw_chan_t (soc_axi_mst_aw_chan_t),
    .axi_w_chan_t  (soc_axi_mst_w_chan_t),
    .axi_ar_chan_t (soc_axi_mst_ar_chan_t),
    .axi_b_chan_t  (soc_axi_mst_b_chan_t),
    .axi_r_chan_t  (soc_axi_mst_r_chan_t)
  ) i_axi_to_apb (
    .clk_i,
    .rst_ni,
    .s_axi_req_i (target_axi_req[1]),
    .s_axi_rsp_o (target_axi_rsp[1]),
    .m_apb_req_o (apb_req),
    .m_apb_rsp_i (apb_rsp)
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
    .dm_req_o,
    .dm_we_o,
    .dm_addr_o,
    .dm_be_o,
    .dm_wdata_o,
    .dm_rdata_i
  );
endmodule
