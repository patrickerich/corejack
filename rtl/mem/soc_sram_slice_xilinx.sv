// SPDX-License-Identifier: Apache-2.0
//
module soc_sram_slice_xilinx #(
  parameter int unsigned NumWords = 32768,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned AddressShift = 3
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [AddrWidth-1:0] addr_i,
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
  // The per-lane stores below are unrolled because a generate-block instance
  // array cannot be indexed by a run-time variable in a hierarchical reference,
  // so the preload covers at most 8 byte lanes. The hardware itself is generic
  // in DataWidth; only this simulation preload is not, hence the guard - a
  // wider slice would otherwise silently load just its low 8 bytes.
  if (NumBytes > 8) begin : gen_validate_load_mem_lanes
    $fatal(1, "soc_sram_slice_xilinx: load_mem supports at most 8 byte lanes");
  end

  task automatic load_mem(string file_path);
    logic [DataWidth-1:0] init_mem [NumWords];

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
