// SPDX-License-Identifier: Apache-2.0
//
// AXI reset-domain bridge: keeps an AXI link protocol-compliant on both of its
// sides when only the initiator side is reset.
//
// The AXI specification (AMBA AXI, ARM IHI 0022) has two rules this block
// exists to uphold:
//
//   1. Handshake ("Handshake process"): once a source asserts VALID, it keeps
//      VALID asserted, and the information it qualifies stable, until the
//      handshake (VALID and READY both high at a rising clock edge).
//   2. Reset ("Reset"): while ARESETn is asserted, a manager drives ARVALID,
//      AWVALID and WVALID low, and a subordinate drives RVALID and BVALID low.
//
// Rule 2 is the one sanctioned way for VALID to drop before its handshake, and
// it assumes one reset per interface: manager and subordinate reset together,
// so both forget a half-finished transfer. CoreJack breaks that assumption on
// purpose. ndmreset resets the core (core_rst_ni) but not the fabric
// (rst_ni), because the debug module needs the fabric during that reset. The
// two sides of this bridge therefore live under different resets:
//
//   - slv side, toward the initiator (CVA6): in the initiator's reset domain.
//     A reset of the initiator puts this interface in reset, and the
//     initiator then drops its valids, mid-transfer if need be, as rule 2
//     allows.
//   - mst side, toward the fabric: on rst_ni, which ndmreset never asserts.
//     Nothing here was reset, so rule 1 still binds every transfer the fabric
//     has seen. The bridge itself is on rst_ni too.
//
// Connected directly, the initiator's legal rule-2 drop is a rule-1 violation
// on the fabric: a write whose AW was accepted loses its W, the write never
// completes, and the isolation stage behind it never drains. The bridge makes
// each side see a compliant peer:
//
//   - Requests to the fabric (rule 1, as manager): each of AW, W and AR keeps
//     a copy of a request presented on mst without its ready. From the next
//     cycle on, the copy - not the initiator - drives that channel until the
//     handshake, so a reset of the initiator can neither drop VALID nor change
//     the payload. While isolate_i is high no new request is presented, so the
//     bridge never raises a VALID it might later have to drop.
//   - Requests from the initiator: every ready is held low while isolate_i is
//     high, so a transfer the bridge completes on behalf of a reset initiator
//     is never acknowledged to the restarted one.
//   - Responses to the initiator (rule 2, as subordinate): BVALID and RVALID
//     are held low while isolate_i is high, so an initiator in reset, or
//     restarted but not yet past isolation, never sees a response to a request
//     issued before its reset.
//   - Responses from the fabric: BREADY and RREADY are forced high while
//     isolate_i is high, so those responses retire without the initiator.
//
// Outside isolation the bridge is transparent: no added latency, and the
// copies load only on a stall.
//
// Contract with the instantiating logic (soc_top):
//
//   - isolate_i includes the initiator's reset combinationally. The reset
//     asserts asynchronously, mid-cycle, so the copy has to be in place
//     already, captured at the edge before the reset.
//   - isolate_i stays high until every transaction the fabric accepted before
//     the reset has completed (axi_isolate's drain). A held request is one of
//     those, so it retires before isolation ends; this is asserted below. It
//     relies on the downstream axi_isolate counting each held request, which
//     it skips only on its NumPending capacity cut, and CVA6's outstanding
//     transactions stay far below that.
//   - The initiator presents each W no later than its AW handshake (CVA6's
//     axi_shim raises them together, and all writes are single-beat). The
//     bridge can hold a W only once it has been presented; it cannot make one
//     up. Also asserted below.
module soc_axi_reset_bridge (
  input  logic                       clk_i,
  input  logic                       rst_ni,
  // High while the initiator is in reset or its pre-reset transactions are
  // still draining.
  input  logic                       isolate_i,
  // Initiator side, in the initiator's reset domain.
  input  soc_bus_pkg::soc_axi_req_t  slv_req_i,
  output soc_bus_pkg::soc_axi_resp_t slv_rsp_o,
  // Fabric side, on rst_ni.
  output soc_bus_pkg::soc_axi_req_t  mst_req_o,
  input  soc_bus_pkg::soc_axi_resp_t mst_rsp_i
);
  // A held request is one presented on mst at the last edge without its
  // ready; its copy drives the channel until the handshake.
  logic                           aw_held_q;
  logic                           w_held_q;
  logic                           ar_held_q;
  logic                           aw_stall;
  logic                           w_stall;
  logic                           ar_stall;
  soc_bus_pkg::soc_axi_aw_chan_t  aw_q;
  soc_bus_pkg::soc_axi_w_chan_t   w_q;
  soc_bus_pkg::soc_axi_ar_chan_t  ar_q;

  assign aw_stall = mst_req_o.aw_valid && !mst_rsp_i.aw_ready;
  assign w_stall  = mst_req_o.w_valid  && !mst_rsp_i.w_ready;
  assign ar_stall = mst_req_o.ar_valid && !mst_rsp_i.ar_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_held_q <= 1'b0;
      w_held_q  <= 1'b0;
      ar_held_q <= 1'b0;
    end else begin
      aw_held_q <= aw_stall;
      w_held_q  <= w_stall;
      ar_held_q <= ar_stall;
    end
  end

  // Load only on the first stalled cycle; while held, mst already carries the
  // copy, so reloading would change nothing.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_q <= '0;
      w_q  <= '0;
      ar_q <= '0;
    end else begin
      if (aw_stall && !aw_held_q) begin
        aw_q <= slv_req_i.aw;
      end
      if (w_stall && !w_held_q) begin
        w_q <= slv_req_i.w;
      end
      if (ar_stall && !ar_held_q) begin
        ar_q <= slv_req_i.ar;
      end
    end
  end

  always_comb begin
    mst_req_o          = slv_req_i;
    mst_req_o.aw_valid = aw_held_q || (slv_req_i.aw_valid && !isolate_i);
    mst_req_o.w_valid  = w_held_q  || (slv_req_i.w_valid  && !isolate_i);
    mst_req_o.ar_valid = ar_held_q || (slv_req_i.ar_valid && !isolate_i);
    if (aw_held_q) begin
      mst_req_o.aw = aw_q;
    end
    if (w_held_q) begin
      mst_req_o.w = w_q;
    end
    if (ar_held_q) begin
      mst_req_o.ar = ar_q;
    end
    mst_req_o.b_ready = slv_req_i.b_ready || isolate_i;
    mst_req_o.r_ready = slv_req_i.r_ready || isolate_i;
  end

  always_comb begin
    slv_rsp_o          = mst_rsp_i;
    slv_rsp_o.aw_ready = mst_rsp_i.aw_ready && !isolate_i;
    slv_rsp_o.w_ready  = mst_rsp_i.w_ready  && !isolate_i;
    slv_rsp_o.ar_ready = mst_rsp_i.ar_ready && !isolate_i;
    slv_rsp_o.b_valid  = mst_rsp_i.b_valid  && !isolate_i;
    slv_rsp_o.r_valid  = mst_rsp_i.r_valid  && !isolate_i;
  end

`ifndef SYNTHESIS
  // Contract checks; see the header.
  logic isolate_q;
  int   w_ahead_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      isolate_q <= 1'b0;
      w_ahead_q <= 0;
    end else begin
      isolate_q <= isolate_i;
      // A held request outliving isolation would be issued for an initiator
      // that has since been reset, and its response would reach the new one.
      if (isolate_q && !isolate_i) begin
        assert (!aw_held_q && !w_held_q && !ar_held_q)
          else $error("soc_axi_reset_bridge: a held request outlived isolation");
      end
      // W beats accepted ahead of their AW. Restarted at each isolation: a W
      // the bridge completed for a reset initiator is not the new one's.
      if (isolate_i) begin
        w_ahead_q <= 0;
      end else begin
        if (slv_req_i.aw_valid && slv_rsp_o.aw_ready) begin
          assert (slv_req_i.w_valid || (w_ahead_q > 0))
            else $error("soc_axi_reset_bridge: AW accepted before its W was presented");
        end
        w_ahead_q <= w_ahead_q
                     + ((slv_req_i.w_valid && slv_rsp_o.w_ready) ? 1 : 0)
                     - ((slv_req_i.aw_valid && slv_rsp_o.aw_ready) ? 1 : 0);
      end
    end
  end
`endif

endmodule
