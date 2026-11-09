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
  // FPGA-friendly placeholder clock gate, as for CV32E40P. The core still observes
  // sleep state, but the local clock is left ungated until a board/library-specific
  // gate is selected.
  //
  // A replacement must not let clk_o rise while clk_i is high. A bare AND gate does:
  // en_i comes from flops on clk_i, so it rises just after the clock edge and hands
  // the core a late edge that the rest of the SoC never sees. See
  // docs/source/cv32e40x_boot_issue.rst.
  logic unused_lib;
  logic unused_en;

  assign unused_lib = ^LIB;
  assign unused_en  = en_i ^ scan_cg_en_i;
  assign clk_o      = clk_i;
endmodule
