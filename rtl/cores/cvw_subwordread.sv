// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// CoreJack rewrite of the upstream CORE-V-Wally subwordread (RV32 subset).
// The module name is mandated by the Wally instantiation site; the cvw_ file
// prefix avoids collisions (style exception: filename != module name).
module subwordread
  import cvw::*;
#(
  parameter cvw_t P
) (
  input  logic [P.LLEN-1:0] ReadDataWordMuxM,
  input  logic [3:0]        PAdrM,
  input  logic [2:0]        Funct3M,
  input  logic              FpLoadStoreM,
  input  logic              BigEndianM,
  output logic [P.LLEN-1:0] ReadDataM
);
  if (P.LLEN == 32) begin : gen_rv32
    logic [1:0]  paddr_swap;
    logic [7:0]  byte_m;
    logic [15:0] halfword_m;
    logic [31:0] word_m;

    if (P.BIGENDIAN_SUPPORTED) begin : gen_big_endian
      assign paddr_swap = PAdrM[1:0] ^ {2{BigEndianM}};
    end else begin : gen_little_endian
      assign paddr_swap = PAdrM[1:0];
    end

    assign word_m     = ReadDataWordMuxM[31:0];
    assign halfword_m = paddr_swap[1] ? word_m[31:16] : word_m[15:0];
    assign byte_m     = paddr_swap[0] ? halfword_m[15:8] : halfword_m[7:0];

    always_comb begin
      unique case (Funct3M)
        3'b000:  ReadDataM = {{24{byte_m[7]}}, byte_m};
        3'b001:  ReadDataM = {{16{halfword_m[15] | FpLoadStoreM}}, halfword_m};
        3'b010:  ReadDataM = word_m;
        3'b100:  ReadDataM = {24'h0, byte_m};
        3'b101:  ReadDataM = {16'h0, halfword_m};
        default: ReadDataM = ReadDataWordMuxM;
      endcase
    end
  end else begin : gen_unsupported_width
    // Only the LLEN==32 subword extraction is implemented in this CoreJack
    // rewrite (the shipped CVW config is RV32 without F/D). Fail at
    // elaboration rather than silently passing the raw bus word through.
    $fatal(1, "cvw_subwordread only supports P.LLEN == 32");

    always_comb begin
      ReadDataM = ReadDataWordMuxM;
    end
  end
endmodule
