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
  soc_bus_pkg::soc_axi_aw_chan_t aw_q;
  soc_bus_pkg::soc_axi_w_chan_t  w_q;
  logic                          have_aw_q;
  logic                          have_w_q;

  logic aw_fire;
  logic w_fire;
  logic hit;
  logic [31:0] code;

  assign aw_fire = req_i.aw_valid && rsp_i.aw_ready;
  assign w_fire  = req_i.w_valid && rsp_i.w_ready;
  assign hit     = ((have_aw_q ? aw_q.addr : req_i.aw.addr) == SimCtrlAddr);
  assign code    = (have_w_q ? w_q.data[31:0] : req_i.w.data[31:0]);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_q           <= '0;
      w_q            <= '0;
      have_aw_q      <= 1'b0;
      have_w_q       <= 1'b0;
      status_valid_o <= 1'b0;
      status_pass_o  <= 1'b0;
      status_code_o  <= '0;
    end else begin
      status_valid_o <= 1'b0;
      status_pass_o  <= 1'b0;
      status_code_o  <= '0;

      if (aw_fire) begin
        aw_q      <= req_i.aw;
        have_aw_q <= 1'b1;
      end
      if (w_fire) begin
        w_q      <= req_i.w;
        have_w_q <= 1'b1;
      end

      if ((have_aw_q || aw_fire) && (have_w_q || w_fire)) begin
        if (hit) begin
          status_valid_o <= 1'b1;
          status_pass_o  <= code[0];
          status_code_o  <= code;
        end
        have_aw_q <= 1'b0;
        have_w_q  <= 1'b0;
      end
    end
  end
endmodule
