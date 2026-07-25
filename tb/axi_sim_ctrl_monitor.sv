// SPDX-License-Identifier: Apache-2.0
//
// Snoops an AXI write channel pair for stores to the sim_ctrl magic address
// and reports the written status word. AW and W beats are queued
// independently and paired FIFO-style, so legal multi-outstanding writes
// (a second AW before the previous W, or same-cycle AW+W completions) can
// never skew the pairing - a depth-1 tracker here silently mispaired the
// status write with an unrelated data beat.
module axi_sim_ctrl_monitor #(
  parameter logic [31:0] SimCtrlAddr = 32'h1000_2000
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  soc_bus_pkg::soc_axi_req_t req_i,
  input  soc_bus_pkg::soc_axi_resp_t rsp_i,
  output logic status_valid_o,
  output logic status_pass_o,
  output logic [31:0] status_code_o
);
  soc_bus_pkg::soc_axi_aw_chan_t aw_fifo [$];
  soc_bus_pkg::soc_axi_w_chan_t  w_fifo  [$];

  logic aw_fire;
  logic w_fire;

  assign aw_fire = req_i.aw_valid && rsp_i.aw_ready;
  assign w_fire  = req_i.w_valid && rsp_i.w_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_fifo.delete();
      w_fifo.delete();
      status_valid_o <= 1'b0;
      status_pass_o  <= 1'b0;
      status_code_o  <= '0;
    end else begin
      automatic soc_bus_pkg::soc_axi_aw_chan_t aw;
      automatic soc_bus_pkg::soc_axi_w_chan_t  w;

      status_valid_o <= 1'b0;
      status_pass_o  <= 1'b0;
      status_code_o  <= '0;

      if (aw_fire) begin
        aw_fifo.push_back(req_i.aw);
      end
      if (w_fire) begin
        w_fifo.push_back(req_i.w);
      end

      if ((aw_fifo.size() > 0) && (w_fifo.size() > 0)) begin
        aw = aw_fifo.pop_front();
        w  = w_fifo.pop_front();
        if (aw.addr == soc_bus_pkg::axi_addr_t'(SimCtrlAddr)) begin
          status_valid_o <= 1'b1;
          status_pass_o  <= w.data[0];
          status_code_o  <= w.data[31:0];
        end
      end
    end
  end
endmodule
