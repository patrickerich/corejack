// SPDX-License-Identifier: Apache-2.0
//
module soc_obi_mem_buffer #(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned ReqFifoDepth = 2,
  parameter int unsigned RspFifoDepth = 2
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic                         s_req_i,
  output logic                         s_gnt_o,
  input  logic                         s_we_i,
  input  logic [AddrWidth-1:0]         s_addr_i,
  input  logic [DataWidth-1:0]         s_wdata_i,
  input  logic [DataWidth/8-1:0]       s_be_i,
  output logic                         s_rvalid_o,
  input  logic                         s_rready_i,
  output logic [DataWidth-1:0]         s_rdata_o,
  output logic                         s_err_o,

  output logic                         m_req_o,
  input  logic                         m_gnt_i,
  output logic                         m_we_o,
  output logic [AddrWidth-1:0]         m_addr_o,
  output logic [DataWidth-1:0]         m_wdata_o,
  output logic [DataWidth/8-1:0]       m_be_o,
  input  logic                         m_rvalid_i,
  output logic                         m_rready_o,
  input  logic [DataWidth-1:0]         m_rdata_i,
  input  logic                         m_err_i
);
  typedef struct packed {
    logic                   we;
    logic [AddrWidth-1:0]   addr;
    logic [DataWidth-1:0]   wdata;
    logic [DataWidth/8-1:0] be;
  } req_payload_t;

  typedef struct packed {
    logic                 err;
    logic [DataWidth-1:0] rdata;
  } rsp_payload_t;

  req_payload_t req_fifo_in;
  req_payload_t req_fifo_out;
  rsp_payload_t rsp_fifo_in;
  rsp_payload_t rsp_fifo_out;
  logic         req_fifo_full;
  logic         req_fifo_empty;
  logic         req_fifo_push;
  logic         req_fifo_pop;
  logic         rsp_fifo_full;
  logic         rsp_fifo_empty;
  logic         rsp_fifo_push;
  logic         rsp_fifo_pop;

  initial begin
    assert (ReqFifoDepth > 0) else $fatal(1, "ReqFifoDepth must be greater than zero");
    assert (RspFifoDepth > 0) else $fatal(1, "RspFifoDepth must be greater than zero");
  end

  assign req_fifo_in = '{
    we:    s_we_i,
    addr:  s_addr_i,
    wdata: s_wdata_i,
    be:    s_be_i
  };

  assign rsp_fifo_in = '{
    err:   m_err_i,
    rdata: m_rdata_i
  };

  assign s_gnt_o       = !req_fifo_full;
  assign req_fifo_push = s_req_i && s_gnt_o;

  assign m_req_o      = !req_fifo_empty;
  assign req_fifo_pop = m_req_o && m_gnt_i;
  assign m_we_o       = req_fifo_out.we;
  assign m_addr_o     = req_fifo_out.addr;
  assign m_wdata_o    = req_fifo_out.wdata;
  assign m_be_o       = req_fifo_out.be;

  // Accept a response only when the FIFO has room *this* cycle: fifo_v3
  // internally gates push_i with ~full_o (full_o is registered), so a
  // full-and-popping cycle would accept the beat on the m side and then
  // silently drop it.
  assign m_rready_o    = !rsp_fifo_full;
  assign rsp_fifo_push = m_rvalid_i && m_rready_o;
  assign s_rvalid_o    = !rsp_fifo_empty;
  assign rsp_fifo_pop  = s_rvalid_o && s_rready_i;
  assign s_rdata_o     = rsp_fifo_out.rdata;
  assign s_err_o       = rsp_fifo_out.err;

  fifo_v3 #(
    .FALL_THROUGH (1'b0),
    .DEPTH        (ReqFifoDepth),
    .dtype        (req_payload_t)
  ) i_req_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (req_fifo_full),
    .empty_o    (req_fifo_empty),
    .usage_o    (),
    .data_i     (req_fifo_in),
    .push_i     (req_fifo_push),
    .data_o     (req_fifo_out),
    .pop_i      (req_fifo_pop)
  );

  fifo_v3 #(
    // Keep the response path registered.  fifo_v3 fall-through mode makes
    // empty_o depend on push_i, which would couple downstream rvalid back
    // into upstream rready in this two-sided handshake bridge.
    .FALL_THROUGH (1'b0),
    .DEPTH        (RspFifoDepth),
    .dtype        (rsp_payload_t)
  ) i_rsp_fifo (
    .clk_i,
    .rst_ni,
    .flush_i    (1'b0),
    .testmode_i (1'b0),
    .full_o     (rsp_fifo_full),
    .empty_o    (rsp_fifo_empty),
    .usage_o    (),
    .data_i     (rsp_fifo_in),
    .push_i     (rsp_fifo_push),
    .data_o     (rsp_fifo_out),
    .pop_i      (rsp_fifo_pop)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(rsp_fifo_push && rsp_fifo_full))
        else $error("soc_obi_mem_buffer response FIFO overflow");
    end
  end
`endif
endmodule
