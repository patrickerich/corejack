// SPDX-License-Identifier: Apache-2.0
//
module soc_sram_slice_xilinx #(
  parameter int unsigned NumWords = 32768,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AddressShift = 3
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [31:0] addr_i,
  input  logic [DataWidth-1:0] wdata_i,
  input  logic [DataWidth/8-1:0]  be_i,
  output logic [DataWidth-1:0] rdata_o
);
  localparam int unsigned IdxWidth = (NumWords > 1) ? $clog2(NumWords) : 1;
  localparam int unsigned NumBytes = DataWidth / 8;

  logic [NumBytes-1:0][7:0] rdata_byte;
  logic [IdxWidth-1:0] word_idx;

  assign word_idx = addr_i[AddressShift + IdxWidth - 1 : AddressShift];

  for (genvar i = 0; i < NumBytes; i++) begin : gen_byte_lanes
    soc_sram_byte_lane_xilinx #(
      .NumWords (NumWords),
      .IdxWidth (IdxWidth)
    ) u_byte_lane (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .req_i   (req_i),
      .we_i    (we_i & be_i[i]),
      .word_i  (word_idx),
      .wdata_i (wdata_i[i*8 +: 8]),
      .rdata_o (rdata_byte[i])
    );
  end

  for (genvar i = 0; i < NumBytes; i++) begin : gen_rdata
    assign rdata_o[i*8 +: 8] = rdata_byte[i];
  end

`ifndef SYNTHESIS
  task automatic load_mem(string file_path);
    logic [DataWidth-1:0] init_mem [0:NumWords-1];

    $readmemh(file_path, init_mem);
    for (int unsigned word = 0; word < NumWords; word++) begin
      if (NumBytes >= 1) begin
        gen_byte_lanes[0].u_byte_lane.mem_q[word] = init_mem[word][0*8 +: 8];
      end
      if (NumBytes >= 2) begin
        gen_byte_lanes[1].u_byte_lane.mem_q[word] = init_mem[word][1*8 +: 8];
      end
      if (NumBytes >= 3) begin
        gen_byte_lanes[2].u_byte_lane.mem_q[word] = init_mem[word][2*8 +: 8];
      end
      if (NumBytes >= 4) begin
        gen_byte_lanes[3].u_byte_lane.mem_q[word] = init_mem[word][3*8 +: 8];
      end
      if (NumBytes >= 5) begin
        gen_byte_lanes[4].u_byte_lane.mem_q[word] = init_mem[word][4*8 +: 8];
      end
      if (NumBytes >= 6) begin
        gen_byte_lanes[5].u_byte_lane.mem_q[word] = init_mem[word][5*8 +: 8];
      end
      if (NumBytes >= 7) begin
        gen_byte_lanes[6].u_byte_lane.mem_q[word] = init_mem[word][6*8 +: 8];
      end
      if (NumBytes >= 8) begin
        gen_byte_lanes[7].u_byte_lane.mem_q[word] = init_mem[word][7*8 +: 8];
      end
    end
  endtask : load_mem
`endif
endmodule

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
  (* ram_style = "block" *) logic [7:0] mem_q [0:NumWords-1];
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
