// SPDX-License-Identifier: Apache-2.0
//
// CoreJack platform-level interrupt controller (PLIC).
//
// Implements the M-mode subset of the RISC-V PLIC specification for a single
// hart context: level-triggered sources, per-source priority and enable, a
// context threshold, and the claim/complete handshake. The register layout
// follows the de-facto standard PLIC memory map (SiFive E/U series, QEMU
// `virt`), so stock Zephyr/Linux PLIC drivers program it unmodified:
//
//   0x000000 + 4*src : priority[src]             (RW, src = 1..NumSources)
//   0x001000 + 4*w   : pending word w            (RO)
//   0x002000 + 4*w   : enable word w, context 0  (RW)
//   0x200000         : threshold, context 0      (RW)
//   0x200004         : claim/complete, context 0 (read claims, write completes)
//
// Source IDs are 1-based (ID 0 is reserved per spec): irq_sources_i[i] drives
// source ID i+1, and bit (ID % 32) of pending/enable word (ID / 32) belongs to
// that source. Sources are level-triggered with the standard gateway rule: a
// pending source latches until claimed, a claimed source cannot pend again
// until completed, and a source still asserted at completion pends again.
// Completion of a source whose enable bit is clear is silently ignored (spec).
//
// A claim read returns the highest-priority pending-and-enabled source with a
// nonzero priority (ties go to the lowest ID) regardless of the threshold;
// the threshold only gates the irq_o (EIP) output. Undecoded offsets read as
// zero and ignore writes; the register port responds in a single cycle.
//
// Sub-word writes are not supported: writes apply the full 32-bit wdata
// whenever any wstrb bit is set (PLIC drivers issue word accesses only).

module soc_plic #(
  parameter int unsigned NumSources = 2,
  parameter int unsigned PrioWidth  = 3,
  parameter type reg_req_t = soc_bus_pkg::soc_reg_req_t,
  parameter type reg_rsp_t = soc_bus_pkg::soc_reg_rsp_t
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  reg_req_t reg_req_i,
  output reg_rsp_t reg_rsp_o,

  input  logic [NumSources-1:0] irq_sources_i,
  output logic                  irq_o
);
  // Pending/enable words cover source IDs 1..NumSources (bit 0 of word 0 is
  // the reserved source 0 and always reads zero).
  localparam int unsigned NumSrcWords = (NumSources + 32) / 32;
  localparam int unsigned SrcIdWidth  = $clog2(NumSources + 1);

  // Standard-layout block offsets (byte addresses within the 4 MiB window).
  localparam logic [31:0] PrioBase      = 32'h0000_0000;
  localparam logic [31:0] PendingBase   = 32'h0000_1000;
  localparam logic [31:0] EnableBase    = 32'h0000_2000;
  localparam logic [31:0] ThresholdAddr = 32'h0020_0000;
  localparam logic [31:0] ClaimAddr     = 32'h0020_0004;

  typedef logic [PrioWidth-1:0] prio_t;

  // Index [i] of every per-source array belongs to source ID i+1.
  prio_t [NumSources-1:0] prio_q;
  logic  [NumSources-1:0] ip_q;
  logic  [NumSources-1:0] en_q;
  logic  [NumSources-1:0] active_q;
  prio_t                  threshold_q;

  // Widened to 32 bits so the block-offset comparisons below are same-width
  // (the offset arithmetic promotes to 32-bit int).
  logic [31:0] req_addr;
  logic        req_read;
  logic        req_write;

  assign req_addr  = 32'(reg_req_i.addr);
  assign req_read  = reg_req_i.valid && !reg_req_i.write;
  assign req_write = reg_req_i.valid && reg_req_i.write && (reg_req_i.wstrb != '0);

  // Claim/complete selection: highest priority among pending-and-enabled
  // sources with a nonzero priority; the lowest ID wins a priority tie.
  logic [SrcIdWidth-1:0] best_id;
  prio_t                 best_prio;

  always_comb begin
    best_id   = '0;
    best_prio = '0;
    for (int unsigned i = NumSources; i > 0; i--) begin
      if (ip_q[i-1] && en_q[i-1] && (prio_q[i-1] != '0) && (prio_q[i-1] >= best_prio)) begin
        best_id   = SrcIdWidth'(i);
        best_prio = prio_q[i-1];
      end
    end
  end

  assign irq_o = (best_id != '0) && (best_prio > threshold_q);

  logic                  claim_fire;
  logic                  complete_fire;
  logic [SrcIdWidth-1:0] complete_id;

  assign claim_fire    = req_read && (req_addr == ClaimAddr) && (best_id != '0);
  assign complete_fire = req_write && (req_addr == ClaimAddr) &&
                         (reg_req_i.wdata >= 1) && (reg_req_i.wdata <= NumSources);
  assign complete_id   = SrcIdWidth'(reg_req_i.wdata);

  // Per-source word/bit decode helpers for the pending and enable blocks.
  function automatic logic [31:0] src_word(input logic [NumSources-1:0] bits,
                                           input logic [31:0] addr);
    logic [31:0] word;
    word = '0;
    for (int unsigned i = 0; i < NumSources; i++) begin
      if (32'((i + 1) / 32) == 32'(addr[11:2])) begin
        word[(i + 1) % 32] = bits[i];
      end
    end
    return word;
  endfunction

  // Single-cycle response; reads of the claim register have the claim side
  // effect (handled in the sequential block below).
  always_comb begin
    reg_rsp_o = '{ready: 1'b1, rdata: 32'h0, error: 1'b0};

    if (req_read) begin
      if ((req_addr >= PrioBase + 4) && (req_addr < PrioBase + 4 * (NumSources + 1)) &&
          (req_addr[1:0] == 2'b00)) begin
        reg_rsp_o.rdata = 32'(prio_q[req_addr[11:2] - 1]);
      end else if ((req_addr >= PendingBase) &&
                   (req_addr < PendingBase + 4 * NumSrcWords)) begin
        reg_rsp_o.rdata = src_word(ip_q, req_addr);
      end else if ((req_addr >= EnableBase) &&
                   (req_addr < EnableBase + 4 * NumSrcWords)) begin
        reg_rsp_o.rdata = src_word(en_q, req_addr);
      end else if (req_addr == ThresholdAddr) begin
        reg_rsp_o.rdata = 32'(threshold_q);
      end else if (req_addr == ClaimAddr) begin
        reg_rsp_o.rdata = 32'(best_id);
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prio_q      <= '0;
      ip_q        <= '0;
      en_q        <= '0;
      active_q    <= '0;
      threshold_q <= '0;
    end else begin
      // Gateway: latch a pending request from an asserted source that is
      // neither already pending nor claimed-but-not-completed.
      for (int unsigned i = 0; i < NumSources; i++) begin
        if (irq_sources_i[i] && !active_q[i]) begin
          ip_q[i] <= 1'b1;
        end
      end

      if (claim_fire) begin
        ip_q[best_id - 1]     <= 1'b0;
        active_q[best_id - 1] <= 1'b1;
      end

      // Completion re-opens the gateway; ignored while the source is disabled.
      if (complete_fire && en_q[complete_id - 1]) begin
        active_q[complete_id - 1] <= 1'b0;
      end

      if (req_write) begin
        if ((req_addr >= PrioBase + 4) && (req_addr < PrioBase + 4 * (NumSources + 1)) &&
            (req_addr[1:0] == 2'b00)) begin
          prio_q[req_addr[11:2] - 1] <= prio_t'(reg_req_i.wdata);
        end else if ((req_addr >= EnableBase) &&
                     (req_addr < EnableBase + 4 * NumSrcWords)) begin
          for (int unsigned i = 0; i < NumSources; i++) begin
            if (32'((i + 1) / 32) == 32'(req_addr[11:2])) begin
              en_q[i] <= reg_req_i.wdata[(i + 1) % 32];
            end
          end
        end else if (req_addr == ThresholdAddr) begin
          threshold_q <= prio_t'(reg_req_i.wdata);
        end
      end
    end
  end

`ifndef SYNTHESIS
  initial begin : validate_params
    if (NumSources == 0 || NumSources > 1023) begin
      $fatal(1, "soc_plic: NumSources must be in 1..1023");
    end
    if (PrioWidth == 0 || PrioWidth > 32) begin
      $fatal(1, "soc_plic: PrioWidth must be in 1..32");
    end
  end
`endif
endmodule
