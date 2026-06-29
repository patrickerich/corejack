// SPDX-License-Identifier: Apache-2.0
//
// soc_mem_ss bank pipeline (elastic).
//
// One bank = one SRAM slice wrapped in a small elastic pipeline:
//   input FIFO -> registered-read SRAM slice -> output FIFO.
// Both FIFOs are parameterizable (default depth 1, the R8 timing-break stages)
// and backpressure: slave upstream (in_ready_o) and master downstream
// (out_valid_o / out_ready_i). The non-stallable 1-cycle SRAM read is applied
// only while the output side has room to catch its result (out_claims_q tracks
// in-flight reads plus queued results). Per-request metadata rides through
// opaquely so the subsystem can route the response to the owning port's
// reorder-buffer slot.
module soc_mem_bank
  import mem_ss_pkg::*;
#(
  parameter int unsigned DataWidth    = 64,
  parameter int unsigned AddrWidth    = 32,
  parameter int unsigned NumWords     = 16384,
  parameter int unsigned AddressShift = $clog2(DataWidth / 8),
  parameter int unsigned MetaWidth    = 1,
  parameter int unsigned InDepth      = 1,
  parameter int unsigned OutDepth     = 1,
  parameter int unsigned BankId       = 0,
  parameter string       MemInitPath  = "",
  parameter mem_impl_e   MemImpl       = MemImplModel
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,

  // Request in (from the per-bank arbiter).
  input  logic                   in_valid_i,
  output logic                   in_ready_o,
  input  logic                   in_we_i,
  input  logic [AddrWidth-1:0]   in_addr_i,
  input  logic [DataWidth-1:0]   in_wdata_i,
  input  logic [DataWidth/8-1:0] in_be_i,
  input  logic [MetaWidth-1:0]   in_meta_i,

  // Response out (to the response crossbar).
  output logic                   out_valid_o,
  input  logic                   out_ready_i,
  output logic [DataWidth-1:0]   out_rdata_o,
  output logic [MetaWidth-1:0]   out_meta_o
);
  localparam int unsigned BeWidth  = DataWidth / 8;
  localparam int unsigned ReqWidth = 1 + AddrWidth + DataWidth + BeWidth + MetaWidth;
  localparam int unsigned RspWidth = DataWidth + MetaWidth;
  localparam int unsigned ClaimW   = $clog2(OutDepth + 1);
  // SRAM slice registered-read latency: the model is 1 cycle, the Xilinx
  // byte-cell pipelines through two registers (2 cycles). Valid + metadata are
  // delayed to match so the response carries the right request.
  localparam int unsigned ReadLat  = (MemImpl == MemImplXilinx) ? 2 : 1;

  // --- Input FIFO (timing break + elasticity on the request side) ---
  logic                in_full, in_empty;
  logic [ReqWidth-1:0] in_din, in_dout;
  logic                in_push, in_pop;

  assign in_din     = {in_we_i, in_addr_i, in_wdata_i, in_be_i, in_meta_i};
  assign in_ready_o = !in_full;
  assign in_push    = in_valid_i & in_ready_o;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(ReqWidth), .DEPTH(InDepth)) i_in_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(in_full), .empty_o(in_empty), .usage_o(),
    .data_i(in_din), .push_i(in_push), .data_o(in_dout), .pop_i(in_pop)
  );

  logic                 head_we;
  logic [AddrWidth-1:0]  head_addr;
  logic [DataWidth-1:0]  head_wdata;
  logic [BeWidth-1:0]    head_be;
  logic [MetaWidth-1:0]  head_meta;
  assign {head_we, head_addr, head_wdata, head_be, head_meta} = in_dout;

  // --- Issue gate: apply a slice access only when the output side has room ---
  logic [ClaimW-1:0] out_claims_q;
  logic              out_full, out_empty;
  logic              out_push, out_pop;
  logic              issue;

  assign issue  = !in_empty && (out_claims_q < ClaimW'(OutDepth));
  assign in_pop = issue;

  // --- SRAM slice (registered read) ---
  logic [DataWidth-1:0] slice_rdata;
  soc_sram_slice_wrapper #(
    .NumWords(NumWords), .DataWidth(DataWidth), .AddressShift(AddressShift), .MemImpl(MemImpl)
  ) i_slice (
    .clk_i, .rst_ni,
    .req_i(issue), .we_i(head_we), .addr_i(head_addr),
    .wdata_i(head_wdata), .be_i(head_be), .rdata_o(slice_rdata)
  );

  // Carry valid + metadata ReadLat cycles to align with the slice read data.
  logic [ReadLat-1:0]                rd_valid_q;
  logic [ReadLat-1:0][MetaWidth-1:0] rd_meta_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_valid_q <= '0;
      rd_meta_q  <= '0;
    end else begin
      rd_valid_q[0] <= issue;
      rd_meta_q[0]  <= head_meta;
      for (int unsigned i = 1; i < ReadLat; i++) begin
        rd_valid_q[i] <= rd_valid_q[i-1];
        rd_meta_q[i]  <= rd_meta_q[i-1];
      end
    end
  end

  // --- Output FIFO (timing break + elasticity on the response side) ---
  assign out_push = rd_valid_q[ReadLat-1];
  logic [RspWidth-1:0] out_dout;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(RspWidth), .DEPTH(OutDepth)) i_out_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(out_full), .empty_o(out_empty), .usage_o(),
    .data_i({slice_rdata, rd_meta_q[ReadLat-1]}), .push_i(out_push), .data_o(out_dout), .pop_i(out_pop)
  );

  assign out_valid_o            = !out_empty;
  assign {out_rdata_o, out_meta_o} = out_dout;
  assign out_pop               = out_valid_o & out_ready_i;

  // Output claims: +1 when a read is issued, -1 when a result is consumed.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_claims_q <= '0;
    end else begin
      out_claims_q <= out_claims_q + ClaimW'(issue) - ClaimW'(out_pop);
    end
  end

`ifndef SYNTHESIS
  assert property (@(posedge clk_i) disable iff (!rst_ni) !(out_push && out_full))
    else $error("soc_mem_bank: output FIFO overflow");

  // Simulation preload: load this bank's interleaved image from
  // <MemInitPath>/bank_<BankId>.hex (or the +MEM_PATH plusarg), matching the
  // build's per-bank hex split.
  initial begin : init_bank_from_file
    string mem_path;
    string file_path;
    if (MemInitPath != "") begin
      mem_path = MemInitPath;
    end else if ($value$plusargs("MEM_PATH=%s", mem_path)) begin
    end else begin
      mem_path = "";
    end
    if (mem_path != "") begin
      if (mem_path[mem_path.len()-1] != "/") begin
        mem_path = {mem_path, "/"};
      end
      file_path = $sformatf("%sbank_%0d.hex", mem_path, BankId);
      $display("soc_mem_bank: loading bank %0d from %s", BankId, file_path);
      i_slice.load_mem(file_path);
    end
  end
`endif
endmodule
