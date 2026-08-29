// SPDX-License-Identifier: Apache-2.0
//
// AXI4 (single-beat) to banked-memory bridge for soc_mem_ss.
//
// The read and write directions are independent engines, each driving its OWN
// soc_mem_ss init port. Because soc_mem_ss is a banked memory (multiple
// single-port slices behind a per-bank round-robin arbiter), a read and a write
// to different banks are serviced in the same cycle; a same-bank conflict is
// resolved by the bank arbiter (one side stalls one cycle via gnt). This
// exploits AXI's independent read/write channels and the memory's bank
// parallelism instead of serializing the two through one FSM/port.
//
// Each engine is **pipelined**, holding up to MaxOutstanding transactions in
// flight. That matters because the round trip through this bridge and the
// memory is long (~9 cycles measured end to end on the iDMA path): a bridge
// that allows one transaction at a time turns the whole of that latency into
// throughput cost, capping a 64-bit port at ~0.11 accesses/cycle against the
// ~1.0 soc_mem_ss itself sustains. Depth is what hides the latency, not a
// shorter pipeline - see docs/source/axi4_fabric.md.
//
// Structure per engine, made simple by soc_mem_ss returning responses to a
// port strictly in order (so no reorder buffer is needed, unlike
// soc_mem_port's egress):
//
//   addr FIFO : accepted AXI request -> memory request   (pop on mem grant)
//   id   FIFO : accepted AXI request -> AXI response     (pop on AXI handshake)
//   rsp  FIFO : memory response      -> AXI response     (pop on AXI handshake)
//
// Never-drop: a request is admitted only while a response slot is reserved for
// it (the outstanding counter below), and mem_*_rready_o additionally
// backpressures the memory whenever the response FIFO is full. Same discipline
// as soc_mem_port - buffers' own full/empty, no credit accounting.
//
// Splitting the engines also removes the former lone-AW deadlock workaround:
// the read engine never waits on the write engine, so a read-to-write coupled
// initiator (e.g. the iDMA doing an in-RAM memcpy) cannot deadlock. A write is
// still admitted only once both AW and W are valid, which is what fixed that
// deadlock; pipelining must not reintroduce accepting a lone AW.
module soc_axi_to_mem
  import axi_pkg::*;
  import soc_bus_pkg::*;
#(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = soc_bus_pkg::AxiDataWidth,
  // Transactions in flight per engine. The iDMA leg wants this deep enough to
  // cover the round trip; the crossbar leg is bounded by the xbar's
  // MaxMstTrans regardless, so a smaller value there costs nothing.
  parameter int unsigned MaxOutstanding = 8,
  // AXI slave-port types. Default to the platform initiator-side types; the
  // platform overrides these with the wider master-side types behind the xbar.
  parameter type axi_req_t     = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_resp_t    = soc_bus_pkg::soc_axi_resp_t,
  parameter type axi_aw_chan_t = soc_bus_pkg::soc_axi_aw_chan_t,
  parameter type axi_w_chan_t  = soc_bus_pkg::soc_axi_w_chan_t,
  parameter type axi_ar_chan_t = soc_bus_pkg::soc_axi_ar_chan_t,
  parameter type axi_b_chan_t  = soc_bus_pkg::soc_axi_b_chan_t,
  parameter type axi_r_chan_t  = soc_bus_pkg::soc_axi_r_chan_t
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  axi_req_t  s_axi_req_i,
  output axi_resp_t s_axi_rsp_o,

  // Read engine init port (mem_rd_we_o is always 0).
  output logic                   mem_rd_req_o,
  output logic                   mem_rd_we_o,
  output logic [AddrWidth-1:0]   mem_rd_addr_o,
  output logic [DataWidth-1:0]   mem_rd_wdata_o,
  output logic [DataWidth/8-1:0] mem_rd_be_o,
  input  logic                   mem_rd_gnt_i,
  input  logic                   mem_rd_rvalid_i,
  output logic                   mem_rd_rready_o,
  input  logic [DataWidth-1:0]   mem_rd_rdata_i,
  input  logic                   mem_rd_err_i,

  // Write engine init port (mem_wr_we_o is always 1; no read data needed).
  output logic                   mem_wr_req_o,
  output logic                   mem_wr_we_o,
  output logic [AddrWidth-1:0]   mem_wr_addr_o,
  output logic [DataWidth-1:0]   mem_wr_wdata_o,
  output logic [DataWidth/8-1:0] mem_wr_be_o,
  input  logic                   mem_wr_gnt_i,
  input  logic                   mem_wr_rvalid_i,
  output logic                   mem_wr_rready_o,
  input  logic                   mem_wr_err_i
);
  localparam int unsigned IdW    = $bits(s_axi_req_i.ar.id);
  localparam int unsigned StrbW  = DataWidth / 8;
  localparam int unsigned CntW   = $clog2(MaxOutstanding + 1);
  localparam int unsigned RdAddrW = AddrWidth;
  localparam int unsigned WrReqW = AddrWidth + DataWidth + StrbW;
  localparam int unsigned RdRspW = DataWidth + 1;

  // ---------------------------------------------------------------------------
  // Read engine: AR/R channels -> read init port.
  // ---------------------------------------------------------------------------
  logic                rd_admit;
  logic [CntW-1:0]     rd_outstanding_q;
  logic                rd_addr_full, rd_addr_empty, rd_addr_pop;
  logic                rd_id_full, rd_id_empty;
  logic                rd_rsp_full, rd_rsp_empty;
  logic [RdAddrW-1:0]  rd_addr_head;
  logic [IdW-1:0]      rd_id_head;
  logic [RdRspW-1:0]   rd_rsp_head;
  logic                rd_r_fire;
  logic                rd_rsp_push;
  // Requests issued to memory but not yet answered. Responses are only taken
  // while this engine actually has one outstanding, so a port that shares its
  // rvalid with the other engine (as the unit harness does) cannot inject a
  // phantom response - the previous FSM had this property implicitly by only
  // sampling rvalid in its wait state.
  logic [CntW-1:0]     rd_pending_q;

  // Admit an AR only while a response slot is reserved for it. Bounding total
  // in-flight to MaxOutstanding is what makes the response FIFO unable to
  // overflow, so no request can be dropped once accepted.
  assign rd_admit = s_axi_req_i.ar_valid && (rd_outstanding_q < CntW'(MaxOutstanding))
                    && !rd_addr_full && !rd_id_full;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(RdAddrW), .DEPTH(MaxOutstanding)) i_rd_addr_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(rd_addr_full), .empty_o(rd_addr_empty), .usage_o(),
    .data_i(AddrWidth'(s_axi_req_i.ar.addr)), .push_i(rd_admit),
    .data_o(rd_addr_head), .pop_i(rd_addr_pop)
  );

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(IdW), .DEPTH(MaxOutstanding)) i_rd_id_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(rd_id_full), .empty_o(rd_id_empty), .usage_o(),
    .data_i(s_axi_req_i.ar.id), .push_i(rd_admit),
    .data_o(rd_id_head), .pop_i(rd_r_fire)
  );

  // Memory request: drive from the address FIFO head until granted.
  assign mem_rd_req_o   = !rd_addr_empty;
  assign mem_rd_we_o    = 1'b0;
  assign mem_rd_addr_o  = rd_addr_head;
  assign mem_rd_wdata_o = '0;
  assign mem_rd_be_o    = '1;
  assign rd_addr_pop    = mem_rd_req_o && mem_rd_gnt_i;

  // Accept memory responses while there is room to hold them.
  assign mem_rd_rready_o = !rd_rsp_full;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(RdRspW), .DEPTH(MaxOutstanding)) i_rd_rsp_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(rd_rsp_full), .empty_o(rd_rsp_empty), .usage_o(),
    .data_i({mem_rd_err_i, mem_rd_rdata_i}),
    .push_i(rd_rsp_push),
    .data_o(rd_rsp_head), .pop_i(rd_r_fire)
  );

  assign rd_rsp_push = mem_rd_rvalid_i && mem_rd_rready_o && (rd_pending_q != '0);

  // R output. Both FIFO heads are stable until popped, so the payload is held
  // while r_valid && !r_ready, as soc_axi_protocol_checker requires.
  assign rd_r_fire = !rd_rsp_empty && !rd_id_empty && s_axi_req_i.r_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_outstanding_q <= '0;
      rd_pending_q     <= '0;
    end else begin
      rd_outstanding_q <= rd_outstanding_q + CntW'(rd_admit) - CntW'(rd_r_fire);
      rd_pending_q     <= rd_pending_q + CntW'(rd_addr_pop) - CntW'(rd_rsp_push);
    end
  end

  // ---------------------------------------------------------------------------
  // Write engine: AW/W/B channels -> write init port. A write competes only
  // once both AW and W are valid (committing on a lone AW is unnecessary and
  // was the old deadlock source); the read engine is independent either way.
  // ---------------------------------------------------------------------------
  logic               wr_admit;
  logic [CntW-1:0]    wr_outstanding_q;
  logic               wr_req_full, wr_req_empty, wr_req_pop;
  logic               wr_id_full, wr_id_empty;
  logic               wr_rsp_full, wr_rsp_empty;
  logic [WrReqW-1:0]  wr_req_head;
  logic [IdW-1:0]     wr_id_head;
  logic               wr_rsp_head;
  logic               wr_b_fire;
  logic               wr_rsp_push;
  logic [CntW-1:0]    wr_pending_q;  // see rd_pending_q

  assign wr_admit = s_axi_req_i.aw_valid && s_axi_req_i.w_valid
                    && (wr_outstanding_q < CntW'(MaxOutstanding))
                    && !wr_req_full && !wr_id_full;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(WrReqW), .DEPTH(MaxOutstanding)) i_wr_req_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(wr_req_full), .empty_o(wr_req_empty), .usage_o(),
    .data_i({AddrWidth'(s_axi_req_i.aw.addr), DataWidth'(s_axi_req_i.w.data),
             s_axi_req_i.w.strb[StrbW-1:0]}),
    .push_i(wr_admit), .data_o(wr_req_head), .pop_i(wr_req_pop)
  );

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(IdW), .DEPTH(MaxOutstanding)) i_wr_id_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(wr_id_full), .empty_o(wr_id_empty), .usage_o(),
    .data_i(s_axi_req_i.aw.id), .push_i(wr_admit),
    .data_o(wr_id_head), .pop_i(wr_b_fire)
  );

  assign mem_wr_req_o   = !wr_req_empty;
  assign mem_wr_we_o    = 1'b1;
  assign {mem_wr_addr_o, mem_wr_wdata_o, mem_wr_be_o} = wr_req_head;
  assign wr_req_pop     = mem_wr_req_o && mem_wr_gnt_i;

  assign mem_wr_rready_o = !wr_rsp_full;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(1), .DEPTH(MaxOutstanding)) i_wr_rsp_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(wr_rsp_full), .empty_o(wr_rsp_empty), .usage_o(),
    .data_i(mem_wr_err_i), .push_i(wr_rsp_push),
    .data_o(wr_rsp_head), .pop_i(wr_b_fire)
  );

  assign wr_rsp_push = mem_wr_rvalid_i && mem_wr_rready_o && (wr_pending_q != '0);

  assign wr_b_fire = !wr_rsp_empty && !wr_id_empty && s_axi_req_i.b_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_outstanding_q <= '0;
      wr_pending_q     <= '0;
    end else begin
      wr_outstanding_q <= wr_outstanding_q + CntW'(wr_admit) - CntW'(wr_b_fire);
      wr_pending_q     <= wr_pending_q + CntW'(wr_req_pop) - CntW'(wr_rsp_push);
    end
  end

  // ---------------------------------------------------------------------------
  // Response channel merge: the two engines drive disjoint AXI response fields.
  // ---------------------------------------------------------------------------
  always_comb begin
    s_axi_rsp_o          = '0;

    s_axi_rsp_o.ar_ready = rd_admit;
    s_axi_rsp_o.r_valid  = !rd_rsp_empty && !rd_id_empty;
    s_axi_rsp_o.r.id     = rd_id_head;
    s_axi_rsp_o.r.data   = rd_rsp_head[DataWidth-1:0];
    s_axi_rsp_o.r.resp   = rd_rsp_head[DataWidth] ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    s_axi_rsp_o.r.last   = 1'b1;
    s_axi_rsp_o.r.user   = '0;

    s_axi_rsp_o.aw_ready = wr_admit;
    s_axi_rsp_o.w_ready  = wr_admit;
    s_axi_rsp_o.b_valid  = !wr_rsp_empty && !wr_id_empty;
    s_axi_rsp_o.b.id     = wr_id_head;
    s_axi_rsp_o.b.resp   = wr_rsp_head ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
    s_axi_rsp_o.b.user   = '0;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      // The fabric's single-beat invariant, checked where a transaction is
      // admitted rather than where it was formerly registered.
      if (rd_admit) begin
        assert (s_axi_req_i.ar.len == '0);
      end
      if (wr_admit) begin
        assert (s_axi_req_i.aw.len == '0);
        assert (s_axi_req_i.w.last);
      end
      // The admission bound must make the response FIFOs unable to overflow,
      // so a response this engine is actually waiting for is never stalled.
      assert (!(mem_rd_rvalid_i && (rd_pending_q != '0) && !mem_rd_rready_o));
      assert (!(mem_wr_rvalid_i && (wr_pending_q != '0) && !mem_wr_rready_o));
    end
  end
`endif
endmodule
