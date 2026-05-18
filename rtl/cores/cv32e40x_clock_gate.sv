module cv32e40x_clock_gate #(
  parameter int unsigned LIB = 0
) (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);
  logic unused_lib;

  assign unused_lib = ^LIB;
  assign clk_o = clk_i & (en_i | scan_cg_en_i);
endmodule
