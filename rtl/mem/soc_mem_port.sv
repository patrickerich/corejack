// SPDX-License-Identifier: Apache-2.0
//
// soc_mem_ss port: per-initiator request/response handling.
//
// One instance per init port, parameterized to a 32- or 64-bit data width
// (DataWidth). It owns:
//   - an in-order ingress FIFO (backpressures the initiator with s_gnt_o),
//   - address decode of the ingress head into a target bank + in-bank address
//     + 32-bit lane, with an out-of-range detector,
//   - 32<->64 lane expand (writes) / select (reads),
//   - an egress reorder buffer: a slot is allocated in request order when the
//     head is granted (by the bank arbiter, or locally for an out-of-range
//     error), the response drops into its tagged slot whenever it completes,
//     and the buffer drains to the initiator in order.
//
// The slot index (arb_slot_o) tags the request to the bank; the response comes
// back as fill_valid_i/fill_slot_i. Out-of-range requests never reach a bank:
// they fill their own slot with err immediately, and the reorder buffer still
// delivers everything in order, so no latency matching is needed.
//
// No credit counters: a request is only offered for grant while the reorder
// buffer has a free slot, which is just its own full/empty - pure backpressure.
module soc_mem_port #(
  parameter int unsigned DataWidth    = 32,
  parameter int unsigned AddrWidth    = 32,
  parameter int unsigned MemDataWidth = 64,
  parameter int unsigned NumBanks     = 8,
  parameter logic [AddrWidth-1:0] BaseAddr  = 32'h8000_0000,
  parameter int unsigned TotalBytes   = NumBanks * 2048 * (MemDataWidth / 8),
  parameter int unsigned IngressDepth = 2,
  parameter int unsigned EgressDepth  = 2,
  parameter int unsigned AddressShift = $clog2(MemDataWidth / 8),
  // Dependent - do not override.
  parameter int unsigned BankSelW     = (NumBanks > 1) ? $clog2(NumBanks) : 1,
  parameter int unsigned SlotW        = (EgressDepth > 1) ? $clog2(EgressDepth) : 1
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,

  // Initiator side.
  input  logic                    s_req_i,
  output logic                    s_gnt_o,
  input  logic                    s_we_i,
  input  logic [AddrWidth-1:0]    s_addr_i,
  input  logic [DataWidth-1:0]    s_wdata_i,
  input  logic [DataWidth/8-1:0]  s_be_i,
  output logic                    s_rvalid_o,
  input  logic                    s_rready_i,
  output logic [DataWidth-1:0]    s_rdata_o,
  output logic                    s_err_o,

  // Request to the per-bank arbiters (the top routes by arb_bank_o).
  output logic                    arb_req_o,
  output logic [BankSelW-1:0]     arb_bank_o,
  output logic                    arb_we_o,
  output logic [AddrWidth-1:0]    arb_addr_o,      // in-bank byte address
  output logic [MemDataWidth-1:0] arb_wdata_o,
  output logic [MemDataWidth/8-1:0] arb_be_o,
  output logic [SlotW-1:0]        arb_slot_o,
  input  logic                    arb_gnt_i,

  // Response fill from the bank response crossbar.
  input  logic                    fill_valid_i,
  input  logic [SlotW-1:0]        fill_slot_i,
  input  logic [MemDataWidth-1:0] fill_rdata_i
);
  localparam int unsigned MemBytes  = MemDataWidth / 8;
  localparam int unsigned ObiBytes  = DataWidth / 8;
  localparam int unsigned LaneCount = MemBytes / ObiBytes;
  localparam int unsigned LaneW     = (LaneCount > 1) ? $clog2(LaneCount) : 1;
  localparam int unsigned IngWidth  = 1 + AddrWidth + DataWidth + (DataWidth / 8);
  localparam int unsigned CntW      = $clog2(EgressDepth + 1);

  // --- Ingress FIFO ---
  logic               ing_full, ing_empty;
  logic [IngWidth-1:0] ing_din, ing_dout;
  logic               ing_push, ing_pop;

  assign ing_din  = {s_we_i, s_addr_i, s_wdata_i, s_be_i};
  assign s_gnt_o  = !ing_full;
  assign ing_push = s_req_i & s_gnt_o;

  fifo_v3 #(.FALL_THROUGH(1'b0), .DATA_WIDTH(IngWidth), .DEPTH(IngressDepth)) i_ing_fifo (
    .clk_i, .rst_ni, .flush_i(1'b0), .testmode_i(1'b0),
    .full_o(ing_full), .empty_o(ing_empty), .usage_o(),
    .data_i(ing_din), .push_i(ing_push), .data_o(ing_dout), .pop_i(ing_pop)
  );

  logic                   h_we;
  logic [AddrWidth-1:0]   h_addr;
  logic [DataWidth-1:0]   h_wdata;
  logic [DataWidth/8-1:0] h_be;
  assign {h_we, h_addr, h_wdata, h_be} = ing_dout;

  // --- Address decode of the ingress head ---
  logic [AddrWidth-1:0] h_off;
  logic [AddrWidth-1:0] h_word;        // 64-bit word index
  logic [BankSelW-1:0]  h_bank;
  logic [AddrWidth-1:0] h_inbank;      // in-bank byte address
  logic [LaneW-1:0]     h_lane;
  logic                 h_in_range;

  assign h_off      = h_addr - BaseAddr;
  assign h_word     = h_off >> AddressShift;
  assign h_bank     = h_word[BankSelW-1:0];
  assign h_inbank   = (h_word >> BankSelW) << AddressShift;
  assign h_lane     = (LaneCount > 1) ? h_addr[$clog2(ObiBytes) +: LaneW] : '0;
  assign h_in_range = (h_addr >= BaseAddr) && (h_off < AddrWidth'(TotalBytes));

  // Lane expand for writes.
  logic [MemDataWidth-1:0]   h_wdata_exp;
  logic [MemDataWidth/8-1:0] h_be_exp;
  always_comb begin
    if (LaneCount > 1) begin
      h_wdata_exp = '0;
      h_be_exp    = '0;
      h_wdata_exp[h_lane * DataWidth +: DataWidth]  = h_wdata;
      h_be_exp[h_lane * (DataWidth/8) +: (DataWidth/8)] = h_be;
    end else begin
      h_wdata_exp = MemDataWidth'(h_wdata);
      h_be_exp    = (MemDataWidth/8)'(h_be);
    end
  end

  // --- Egress reorder buffer ---
  logic [EgressDepth-1:0]                 rob_filled_q;
  logic [EgressDepth-1:0][DataWidth-1:0]  rob_data_q;
  logic [EgressDepth-1:0]                 rob_err_q;
  logic [EgressDepth-1:0][LaneW-1:0]      rob_lane_q;
  logic [SlotW-1:0]                       alloc_ptr_q, deliver_ptr_q;
  logic [CntW-1:0]                        rob_cnt_q;

  logic rob_full, rob_empty;
  assign rob_full  = (rob_cnt_q == CntW'(EgressDepth));
  assign rob_empty = (rob_cnt_q == '0);

  // Head can be offered for grant when it is valid, in range, and a slot is free.
  assign arb_req_o   = !ing_empty && h_in_range && !rob_full;
  assign arb_bank_o  = h_bank;
  assign arb_we_o    = h_we;
  assign arb_addr_o  = h_inbank;
  assign arb_wdata_o = h_wdata_exp;
  assign arb_be_o    = h_be_exp;
  assign arb_slot_o  = alloc_ptr_q;

  // Local out-of-range error grant (no bank involved).
  logic err_grant;
  assign err_grant = !ing_empty && !h_in_range && !rob_full;

  logic alloc;
  assign alloc   = arb_gnt_i | err_grant;
  assign ing_pop = alloc;

  // Lane-selected read data for a fill.
  logic [DataWidth-1:0] fill_data_sel;
  assign fill_data_sel = (LaneCount > 1) ?
    fill_rdata_i[rob_lane_q[fill_slot_i] * DataWidth +: DataWidth] :
    fill_rdata_i[DataWidth-1:0];

  // Deliver the head slot in order.
  assign s_rvalid_o = !rob_empty && rob_filled_q[deliver_ptr_q];
  assign s_rdata_o  = rob_data_q[deliver_ptr_q];
  assign s_err_o    = rob_err_q[deliver_ptr_q];

  logic deliver;
  assign deliver = s_rvalid_o & s_rready_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rob_filled_q  <= '0;
      rob_err_q     <= '0;
      alloc_ptr_q   <= '0;
      deliver_ptr_q <= '0;
      rob_cnt_q     <= '0;
    end else begin
      // Allocate a slot on grant (bank or error).
      if (alloc) begin
        rob_lane_q[alloc_ptr_q] <= h_lane;
        if (err_grant) begin
          rob_filled_q[alloc_ptr_q] <= 1'b1;
          rob_err_q[alloc_ptr_q]    <= 1'b1;
          rob_data_q[alloc_ptr_q]   <= '0;
        end else begin
          rob_filled_q[alloc_ptr_q] <= 1'b0;
          rob_err_q[alloc_ptr_q]    <= 1'b0;
        end
        alloc_ptr_q <= (alloc_ptr_q == SlotW'(EgressDepth - 1)) ? '0 : alloc_ptr_q + 1'b1;
      end
      // Fill a slot when a bank response returns.
      if (fill_valid_i) begin
        rob_filled_q[fill_slot_i] <= 1'b1;
        rob_data_q[fill_slot_i]   <= fill_data_sel;
        rob_err_q[fill_slot_i]    <= 1'b0;
      end
      // Deliver the head slot.
      if (deliver) begin
        rob_filled_q[deliver_ptr_q] <= 1'b0;
        deliver_ptr_q <= (deliver_ptr_q == SlotW'(EgressDepth - 1)) ? '0 : deliver_ptr_q + 1'b1;
      end
      // Occupancy.
      rob_cnt_q <= rob_cnt_q + CntW'(alloc) - CntW'(deliver);
    end
  end

`ifndef SYNTHESIS
  // A fill must target an allocated-but-unfilled slot.
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    fill_valid_i |-> !rob_filled_q[fill_slot_i])
    else $error("soc_mem_port: fill into an already-filled slot %0d", fill_slot_i);
`endif
endmodule
