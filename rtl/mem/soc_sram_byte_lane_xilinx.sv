// SPDX-License-Identifier: Apache-2.0
//
// One 8-bit lane of a soc_sram_slice_xilinx: a byte-enable is realized as a
// per-lane write enable so the block RAM inference stays clean. Read data is
// registered twice (RAM output register + pipeline register), giving the
// Xilinx slice its 2-cycle read latency.
module soc_sram_byte_lane_xilinx #(
  parameter int unsigned NumWords = 32768,
  parameter int unsigned IdxWidth = 15
) (
  input  logic              clk_i,
  input  logic              rst_ni,
  input  logic              req_i,
  input  logic              we_i,
  input  logic [IdxWidth-1:0] word_i,
  input  logic [7:0]        wdata_i,
  output logic [7:0]        rdata_o
);
  (* ram_style = "block" *) logic [7:0] mem_q [NumWords];
  logic [7:0] rdata_q;
  logic unused_rst_ni;

  assign unused_rst_ni = rst_ni;

  always_ff @(posedge clk_i) begin
    rdata_o <= rdata_q;
    if (req_i) begin
      rdata_q <= mem_q[word_i];
      if (we_i) begin
        mem_q[word_i] <= wdata_i;
      end
    end
  end
endmodule
