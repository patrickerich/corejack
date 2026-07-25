// SPDX-License-Identifier: Apache-2.0
//
// CoreJack shim; the module name is mandated by the CV32E40X integration
// contract, hence filename == vendor module name rather than a corejack_
// prefix.
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
