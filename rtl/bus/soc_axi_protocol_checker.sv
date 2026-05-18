module soc_axi_protocol_checker (
  input  logic clk_i,
  input  logic rst_ni,
  input  soc_bus_pkg::soc_axi_req_t  req_i,
  input  soc_bus_pkg::soc_axi_resp_t rsp_i
);
`ifndef SYNTHESIS
  soc_bus_pkg::soc_axi_aw_chan_t aw_hold_q;
  soc_bus_pkg::soc_axi_w_chan_t  w_hold_q;
  soc_bus_pkg::soc_axi_ar_chan_t ar_hold_q;
  soc_bus_pkg::soc_axi_b_chan_t  b_hold_q;
  soc_bus_pkg::soc_axi_r_chan_t  r_hold_q;
  logic aw_wait_q;
  logic w_wait_q;
  logic ar_wait_q;
  logic b_wait_q;
  logic r_wait_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_hold_q <= '0;
      w_hold_q  <= '0;
      ar_hold_q <= '0;
      b_hold_q  <= '0;
      r_hold_q  <= '0;
      aw_wait_q <= 1'b0;
      w_wait_q  <= 1'b0;
      ar_wait_q <= 1'b0;
      b_wait_q  <= 1'b0;
      r_wait_q  <= 1'b0;
    end else begin
      if (aw_wait_q) begin
        assert (req_i.aw_valid);
        assert (req_i.aw == aw_hold_q);
      end
      if (w_wait_q) begin
        assert (req_i.w_valid);
        assert (req_i.w == w_hold_q);
      end
      if (ar_wait_q) begin
        assert (req_i.ar_valid);
        assert (req_i.ar == ar_hold_q);
      end
      if (b_wait_q) begin
        assert (rsp_i.b_valid);
        assert (rsp_i.b == b_hold_q);
      end
      if (r_wait_q) begin
        assert (rsp_i.r_valid);
        assert (rsp_i.r == r_hold_q);
      end

      if (req_i.aw_valid) begin
        assert (req_i.aw.len == '0);
      end
      if (req_i.ar_valid) begin
        assert (req_i.ar.len == '0);
      end
      if (req_i.w_valid) begin
        assert (req_i.w.last);
      end

      aw_wait_q <= req_i.aw_valid && !rsp_i.aw_ready;
      w_wait_q  <= req_i.w_valid && !rsp_i.w_ready;
      ar_wait_q <= req_i.ar_valid && !rsp_i.ar_ready;
      b_wait_q  <= rsp_i.b_valid && !req_i.b_ready;
      r_wait_q  <= rsp_i.r_valid && !req_i.r_ready;

      if (req_i.aw_valid && !rsp_i.aw_ready) begin
        aw_hold_q <= req_i.aw;
      end
      if (req_i.w_valid && !rsp_i.w_ready) begin
        w_hold_q <= req_i.w;
      end
      if (req_i.ar_valid && !rsp_i.ar_ready) begin
        ar_hold_q <= req_i.ar;
      end
      if (rsp_i.b_valid && !req_i.b_ready) begin
        b_hold_q <= rsp_i.b;
      end
      if (rsp_i.r_valid && !req_i.r_ready) begin
        r_hold_q <= rsp_i.r;
      end
    end
  end
`endif
endmodule
