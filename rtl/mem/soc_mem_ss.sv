// SPDX-License-Identifier: Apache-2.0
//
// soc_mem_ss (redesign): banked, interleaved memory subsystem.
//
// See docs/source/mem_ss_redesign.md for the full specification. Summary:
//   - NumBanks interleaved 64-bit SRAM slices, each wrapped in an elastic
//     soc_mem_bank pipe (timing break + backpressure, never drops).
//   - NumPorts32 32-bit + NumPorts64 64-bit symmetric initiator ports, each a
//     soc_mem_port (ingress FIFO + egress reorder buffer + lane/decode/error).
//   - Per-bank fair round-robin arbitration (rr_arb_tree), so no initiator is
//     starved (R9/R13).
//   - A request crossbar routes each port's decoded head to its target bank's
//     arbiter; a response crossbar routes each bank's result back to the owning
//     port's reorder-buffer slot, arbitrating per port so two banks finishing
//     for the same port in one cycle backpressure instead of colliding.
//
// 64-bit-word interleaving: 64-bit word i lives in bank i mod NumBanks.
module soc_mem_ss
  import mem_ss_pkg::*;
#(
  parameter int unsigned NumPorts32   = 2,
  parameter int unsigned NumPorts64   = 2,
  parameter int unsigned NumBanks     = 8,
  parameter int unsigned MemDataWidth = 64,
  parameter int unsigned AddrWidth    = 32,
  parameter int unsigned WordsPerBank = 2048,
  parameter logic [AddrWidth-1:0] BaseAddr = 32'h8000_0000,
  // Outstanding/buffer depths. These set the throughput ceiling: a port
  // sustains EgressDepth / (ReadLat + 4) accesses per cycle (the reorder-buffer
  // slot round trip from grant to release), and a bank sustains
  // SliceOutDepth / (ReadLat + 2). The defaults below put both at ~1 per cycle
  // for the 2-cycle Xilinx slice, so the subsystem is not the limiter even
  // though today's initiators issue far fewer outstanding requests.
  // SliceInDepth must stay >= 2: a depth-1 fifo_v3 blocks its push while full,
  // which alone would halve the per-bank rate.
  parameter int unsigned IngressDepth = 2,
  parameter int unsigned EgressDepth  = 8,
  parameter int unsigned SliceInDepth = 2,
  parameter int unsigned SliceOutDepth = 4,
  parameter string       MemInitPath  = "",
  parameter mem_impl_e   MemImpl       = MemImplModel,
  // Floor the declared port-group width so a zero-sized group (NumPorts32 or
  // NumPorts64 == 0, i.e. an all-other-width configuration) does not create a
  // [-1:0] reversed range. The generate loops below still use the true counts.
  localparam int unsigned Np32 = (NumPorts32 == 0) ? 1 : NumPorts32,
  localparam int unsigned Np64 = (NumPorts64 == 0) ? 1 : NumPorts64
) (
  input  logic clk_i,
  input  logic rst_ni,

  // 32-bit-data ports.
  input  logic [Np32-1:0]                 req32_i,
  output logic [Np32-1:0]                 gnt32_o,
  input  logic [Np32-1:0]                 we32_i,
  input  logic [Np32-1:0][AddrWidth-1:0]  addr32_i,
  input  logic [Np32-1:0][31:0]           wdata32_i,
  input  logic [Np32-1:0][3:0]            be32_i,
  output logic [Np32-1:0]                 rvalid32_o,
  input  logic [Np32-1:0]                 rready32_i,
  output logic [Np32-1:0][31:0]           rdata32_o,
  output logic [Np32-1:0]                 err32_o,

  // 64-bit-data ports.
  input  logic [Np64-1:0]                 req64_i,
  output logic [Np64-1:0]                 gnt64_o,
  input  logic [Np64-1:0]                 we64_i,
  input  logic [Np64-1:0][AddrWidth-1:0]  addr64_i,
  input  logic [Np64-1:0][63:0]           wdata64_i,
  input  logic [Np64-1:0][7:0]            be64_i,
  output logic [Np64-1:0]                 rvalid64_o,
  input  logic [Np64-1:0]                 rready64_i,
  output logic [Np64-1:0][63:0]           rdata64_o,
  output logic [Np64-1:0]                 err64_o
);
  localparam int unsigned NumPorts   = NumPorts32 + NumPorts64;
  localparam int unsigned PortIdW    = (NumPorts > 1) ? $clog2(NumPorts) : 1;
  localparam int unsigned SlotW      = (EgressDepth > 1) ? $clog2(EgressDepth) : 1;
  localparam int unsigned BankSelW   = (NumBanks > 1) ? $clog2(NumBanks) : 1;
  localparam int unsigned MetaW      = PortIdW + SlotW;
  localparam int unsigned MemBytes   = MemDataWidth / 8;
  localparam int unsigned AddrShift  = $clog2(MemBytes);
  localparam int unsigned PayW       = 1 + AddrWidth + MemDataWidth + MemBytes + MetaW;
  localparam int unsigned TotalBytes = NumBanks * WordsPerBank * MemBytes;

  // Normalized per-port request/response signals (all 64-bit internally).
  logic [NumPorts-1:0]                   p_arb_req, p_arb_gnt, p_arb_we;
  logic [NumPorts-1:0][BankSelW-1:0]     p_arb_bank;
  logic [NumPorts-1:0][AddrWidth-1:0]    p_arb_addr;
  logic [NumPorts-1:0][MemDataWidth-1:0] p_arb_wdata;
  logic [NumPorts-1:0][MemBytes-1:0]     p_arb_be;
  logic [NumPorts-1:0][SlotW-1:0]        p_arb_slot;
  logic [NumPorts-1:0]                   p_fill_valid;
  logic [NumPorts-1:0][SlotW-1:0]        p_fill_slot;
  logic [NumPorts-1:0][MemDataWidth-1:0] p_fill_rdata;

  // --- Ports ---
  for (genvar g = 0; g < NumPorts32; g++) begin : gen_p32
    soc_mem_port #(
      .DataWidth(32), .AddrWidth(AddrWidth), .MemDataWidth(MemDataWidth),
      .NumBanks(NumBanks), .BaseAddr(BaseAddr), .TotalBytes(TotalBytes),
      .IngressDepth(IngressDepth), .EgressDepth(EgressDepth), .AddressShift(AddrShift)
    ) i_port (
      .clk_i, .rst_ni,
      .s_req_i(req32_i[g]), .s_gnt_o(gnt32_o[g]), .s_we_i(we32_i[g]),
      .s_addr_i(addr32_i[g]), .s_wdata_i(wdata32_i[g]), .s_be_i(be32_i[g]),
      .s_rvalid_o(rvalid32_o[g]), .s_rready_i(rready32_i[g]),
      .s_rdata_o(rdata32_o[g]), .s_err_o(err32_o[g]),
      .arb_req_o(p_arb_req[g]), .arb_bank_o(p_arb_bank[g]), .arb_we_o(p_arb_we[g]),
      .arb_addr_o(p_arb_addr[g]), .arb_wdata_o(p_arb_wdata[g]), .arb_be_o(p_arb_be[g]),
      .arb_slot_o(p_arb_slot[g]), .arb_gnt_i(p_arb_gnt[g]),
      .fill_valid_i(p_fill_valid[g]), .fill_slot_i(p_fill_slot[g]),
      .fill_rdata_i(p_fill_rdata[g])
    );
  end

  for (genvar g = 0; g < NumPorts64; g++) begin : gen_p64
    localparam int unsigned P = NumPorts32 + g;
    soc_mem_port #(
      .DataWidth(64), .AddrWidth(AddrWidth), .MemDataWidth(MemDataWidth),
      .NumBanks(NumBanks), .BaseAddr(BaseAddr), .TotalBytes(TotalBytes),
      .IngressDepth(IngressDepth), .EgressDepth(EgressDepth), .AddressShift(AddrShift)
    ) i_port (
      .clk_i, .rst_ni,
      .s_req_i(req64_i[g]), .s_gnt_o(gnt64_o[g]), .s_we_i(we64_i[g]),
      .s_addr_i(addr64_i[g]), .s_wdata_i(wdata64_i[g]), .s_be_i(be64_i[g]),
      .s_rvalid_o(rvalid64_o[g]), .s_rready_i(rready64_i[g]),
      .s_rdata_o(rdata64_o[g]), .s_err_o(err64_o[g]),
      .arb_req_o(p_arb_req[P]), .arb_bank_o(p_arb_bank[P]), .arb_we_o(p_arb_we[P]),
      .arb_addr_o(p_arb_addr[P]), .arb_wdata_o(p_arb_wdata[P]), .arb_be_o(p_arb_be[P]),
      .arb_slot_o(p_arb_slot[P]), .arb_gnt_i(p_arb_gnt[P]),
      .fill_valid_i(p_fill_valid[P]), .fill_slot_i(p_fill_slot[P]),
      .fill_rdata_i(p_fill_rdata[P])
    );
  end

  // Tie off an unused (zero-sized) port group so its floored 1-wide outputs are
  // driven; the matching inputs are simply unread.
  if (NumPorts32 == 0) begin : gen_no_p32
    assign gnt32_o    = '0;
    assign rvalid32_o = '0;
    assign rdata32_o  = '0;
    assign err32_o    = '0;
  end
  if (NumPorts64 == 0) begin : gen_no_p64
    assign gnt64_o    = '0;
    assign rvalid64_o = '0;
    assign rdata64_o  = '0;
    assign err64_o    = '0;
  end

  // --- Bank arbiters + banks ---
  logic [NumBanks-1:0]              bank_in_valid, bank_in_ready;
  logic [NumBanks-1:0]              bank_out_valid, bank_out_ready;
  logic [NumBanks-1:0][MemDataWidth-1:0] bank_out_rdata;
  logic [NumBanks-1:0][MetaW-1:0]   bank_out_meta;
  logic [NumBanks-1:0][NumPorts-1:0] bank_gnt;  // per-bank, per-port grant

  for (genvar b = 0; b < NumBanks; b++) begin : gen_bank
    logic [NumPorts-1:0]            req_b;
    logic [NumPorts-1:0][PayW-1:0]  data_b;
    logic [PayW-1:0]                won_pay;

    for (genvar p = 0; p < NumPorts; p++) begin : gen_req
      assign req_b[p]  = p_arb_req[p] && (p_arb_bank[p] == BankSelW'(b));
      assign data_b[p] = {p_arb_we[p], p_arb_addr[p], p_arb_wdata[p], p_arb_be[p],
                          PortIdW'(p), p_arb_slot[p]};
    end

    rr_arb_tree #(
      .NumIn(NumPorts), .DataWidth(PayW), .LockIn(1'b1), .FairArb(1'b1)
    ) i_arb (
      .clk_i, .rst_ni, .flush_i(1'b0), .rr_i('0),
      .req_i(req_b), .gnt_o(bank_gnt[b]), .data_i(data_b),
      .req_o(bank_in_valid[b]), .gnt_i(bank_in_ready[b]),
      .data_o(won_pay), .idx_o()
    );

    logic                    bk_we;
    logic [AddrWidth-1:0]    bk_addr;
    logic [MemDataWidth-1:0] bk_wdata;
    logic [MemBytes-1:0]     bk_be;
    logic [MetaW-1:0]        bk_meta;
    assign {bk_we, bk_addr, bk_wdata, bk_be, bk_meta} = won_pay;

    soc_mem_bank #(
      .DataWidth(MemDataWidth), .AddrWidth(AddrWidth), .NumWords(WordsPerBank),
      .AddressShift(AddrShift), .MetaWidth(MetaW),
      .InDepth(SliceInDepth), .OutDepth(SliceOutDepth),
      .BankId(b), .MemInitPath(MemInitPath), .MemImpl(MemImpl)
    ) i_bank (
      .clk_i, .rst_ni,
      .in_valid_i(bank_in_valid[b]), .in_ready_o(bank_in_ready[b]),
      .in_we_i(bk_we), .in_addr_i(bk_addr), .in_wdata_i(bk_wdata),
      .in_be_i(bk_be), .in_meta_i(bk_meta),
      .out_valid_o(bank_out_valid[b]), .out_ready_i(bank_out_ready[b]),
      .out_rdata_o(bank_out_rdata[b]), .out_meta_o(bank_out_meta[b])
    );
  end

  // Port grant = the (single) bank whose arbiter granted it.
  always_comb begin
    p_arb_gnt = '0;
    for (int unsigned p = 0; p < NumPorts; p++) begin
      for (int unsigned b = 0; b < NumBanks; b++) begin
        if (bank_gnt[b][p]) p_arb_gnt[p] = 1'b1;
      end
    end
  end

  // --- Response crossbar: per port, pick the lowest-index bank targeting it ---
  always_comb begin
    p_fill_valid   = '0;
    p_fill_slot    = '0;
    p_fill_rdata   = '0;
    bank_out_ready = '0;
    for (int unsigned p = 0; p < NumPorts; p++) begin
      for (int unsigned b = 0; b < NumBanks; b++) begin
        logic [PortIdW-1:0] mport;
        logic [SlotW-1:0]   mslot;
        mport = bank_out_meta[b][MetaW-1 -: PortIdW];
        mslot = bank_out_meta[b][SlotW-1:0];
        if (bank_out_valid[b] && (mport == PortIdW'(p)) && !p_fill_valid[p]) begin
          p_fill_valid[p]   = 1'b1;
          p_fill_slot[p]    = mslot;
          p_fill_rdata[p]   = bank_out_rdata[b];
          bank_out_ready[b] = 1'b1;
        end
      end
    end
  end

  // The soc_mem_port bank/in-bank address decode is bit-sliced, so it only
  // realizes word-mod / word-div for a power-of-two bank count >= 2. A
  // non-power-of-two NumBanks (or NumBanks == 1) would route 64-bit words to
  // phantom banks and deadlock the owning port. The check is a generate-scope
  // elaboration task (not guarded by SYNTHESIS) so synthesis-only flows fail
  // loudly too instead of building broken hardware.
  if ((NumBanks < 2) || ((NumBanks & (NumBanks - 1)) != 0)) begin : gen_validate_num_banks
    $fatal(1, "soc_mem_ss: NumBanks must be a power of two >= 2");
  end
endmodule
