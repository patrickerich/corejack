// SPDX-License-Identifier: Apache-2.0
//
module sim_ctrl_monitor #(
  parameter logic [31:0] SimCtrlAddr = 32'h1000_2000
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic data_req_i,
  input  logic data_we_i,
  input  logic [31:0] data_addr_i,
  input  logic [31:0] data_wdata_i,
  output logic status_valid_o,
  output logic status_pass_o,
  output logic [31:0] status_code_o
);
  logic sim_ctrl_level_q;
  logic sim_ctrl_level;

  always_comb begin
    sim_ctrl_level = data_req_i && data_we_i && (data_addr_i == SimCtrlAddr);
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sim_ctrl_level_q <= 1'b0;
      status_valid_o   <= 1'b0;
      status_pass_o    <= 1'b0;
      status_code_o    <= '0;
    end else begin
      status_valid_o <= 1'b0;
      status_pass_o  <= 1'b0;
      status_code_o  <= '0;

      if (sim_ctrl_level && !sim_ctrl_level_q) begin
        status_valid_o <= 1'b1;
        status_pass_o  <= data_wdata_i[0];
        status_code_o  <= data_wdata_i;
      end

      sim_ctrl_level_q <= sim_ctrl_level;
    end
  end
endmodule
