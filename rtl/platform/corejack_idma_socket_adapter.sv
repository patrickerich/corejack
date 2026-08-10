// SPDX-License-Identifier: Apache-2.0
//
// iDMA tenant of the accelerator socket (accel_socket_if).
//
// Wraps the unchanged soc_idma engine and adapts it to the socket contract:
// - CSR leg: the socket's APB stream is converted with apb_to_reg_v2 (latched,
//   APB-spec timing) into the register interface the idma_reg32_3d frontend
//   speaks. Addresses arrive window-relative from soc_axi_to_apb, so the
//   engine's register offsets (and sw/c/common/dma.h) are unchanged.
// - IRQ leg: a sticky completion flag, set by the engine's one-cycle
//   transfer-retire pulse and cleared by software writing 1 to bit 0 of the
//   IRQ status register at window offset 0xF00 (reads return the flag in
//   bit 0). The flag drives the socket's level-sensitive irq_o, which the
//   platform routes to PLIC source 2. Interrupt handlers acknowledge here
//   first and complete at the PLIC second, or the still-high level pends
//   again immediately.
// - Memory leg: the engine's burst-split, single-beat AXI manager passes
//   through to the socket's mem port.
// - Power intent: no platform power controller exists yet; the pins must sit
//   in the static active state (checked by a sim-only assertion).

module corejack_idma_socket_adapter (
  accel_socket_if.accel sock
);
  import soc_bus_pkg::*;

  localparam logic [11:0] IrqStatusOffset = 12'hF00;

  soc_reg_req_t csr_reg_req;
  soc_reg_rsp_t csr_reg_rsp;
  soc_reg_req_t dma_reg_req;
  soc_reg_rsp_t dma_reg_rsp;

  logic sel_irq_reg;
  logic irq_q;
  logic dma_done;

  apb_to_reg_v2 #(
    // The feedthrough variant never drives reg_req_o.valid; use the latched,
    // APB-spec-conformant path.
    .Feedthrough (1'b0),
    .reg_req_t   (soc_reg_req_t),
    .reg_rsp_t   (soc_reg_rsp_t)
  ) i_apb_to_reg (
    .clk_i     (sock.clk),
    .rst_ni    (sock.rst_n),
    .penable_i (sock.csr_req.penable),
    .pwrite_i  (sock.csr_req.pwrite),
    .paddr_i   (32'(sock.csr_req.paddr)),
    .psel_i    (sock.csr_req.psel),
    .pwdata_i  (sock.csr_req.pwdata),
    .prdata_o  (sock.csr_rsp.prdata),
    .pready_o  (sock.csr_rsp.pready),
    .pslverr_o (sock.csr_rsp.pslverr),
    .reg_req_o (csr_reg_req),
    .reg_rsp_i (csr_reg_rsp)
  );

  // Split the CSR stream: the CoreJack IRQ status register is handled here,
  // everything else goes to the engine's register frontend.
  assign sel_irq_reg = (csr_reg_req.addr[11:0] == IrqStatusOffset);

  always_comb begin
    dma_reg_req       = csr_reg_req;
    dma_reg_req.valid = csr_reg_req.valid && !sel_irq_reg;

    if (sel_irq_reg) begin
      csr_reg_rsp = '{ready: 1'b1, rdata: 32'(irq_q), error: 1'b0};
    end else begin
      csr_reg_rsp = dma_reg_rsp;
    end
  end

  // Sticky completion interrupt: set on transfer retire, W1C from software.
  // A retire coinciding with the clear wins so a completion is never lost.
  always_ff @(posedge sock.clk or negedge sock.rst_n) begin
    if (!sock.rst_n) begin
      irq_q <= 1'b0;
    end else if (dma_done) begin
      irq_q <= 1'b1;
    end else if (csr_reg_req.valid && csr_reg_req.write && sel_irq_reg &&
                 csr_reg_req.wstrb[0] && csr_reg_req.wdata[0]) begin
      // wstrb[0] qualifies the clear: byte 0 carries the W1C bit, so a write
      // that does not strobe it must not clear the flag whatever wdata holds.
      irq_q <= 1'b0;
    end
  end

  assign sock.irq_o = irq_q;

  soc_idma i_soc_idma (
    .clk_i       (sock.clk),
    .rst_ni      (sock.rst_n),
    .reg_req_i   (dma_reg_req),
    .reg_rsp_o   (dma_reg_rsp),
    .m_axi_req_o (sock.mem_req),
    .m_axi_rsp_i (sock.mem_rsp),
    .busy_o      (/* status not routed; software polls DONE_ID or uses irq */),
    .done_o      (dma_done)
  );

`ifndef SYNTHESIS
  always_ff @(posedge sock.clk) begin
    if (sock.rst_n) begin
      assert (sock.power_en && !sock.isolate && !sock.retain && sock.clk_en)
        else $error("accel socket power pins must be in the static active state");
    end
  end
`endif
endmodule
