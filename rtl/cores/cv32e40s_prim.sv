// SPDX-License-Identifier: Apache-2.0
//
// CoreJack shims for the CV32E40S technology primitives. Module names
// (cv32e40s_clock_gate, cv32e40s_sffr, cv32e40s_sffs) are mandated by the
// vendor integration contract; they are grouped in this one file (style
// exception to one-module-per-file) because they are three tiny cells of
// the same primitive library slot.
module cv32e40s_clock_gate #(
  parameter int unsigned LIB = 0
) (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);
  logic unused_lib;
  logic unused_en;

  assign unused_lib = ^LIB;
  assign unused_en = en_i ^ scan_cg_en_i;

  // FPGA-friendly placeholder clock gate. Keep the core in one clock domain;
  // a real gate can be selected later through a board/library-specific cell.
  assign clk_o = clk_i;
endmodule

module cv32e40s_sffr #(
  parameter int unsigned LIB = 0
) (
  input  logic clk,
  input  logic rst_n,
  input  logic d_i,
  output logic q_o
);
  logic unused_lib;

  assign unused_lib = ^LIB;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_o <= 1'b0;
    end else begin
      q_o <= d_i;
    end
  end
endmodule

module cv32e40s_sffs #(
  parameter int unsigned LIB = 0
) (
  input  logic clk,
  input  logic rst_n,
  input  logic d_i,
  output logic q_o
);
  logic unused_lib;

  assign unused_lib = ^LIB;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_o <= 1'b1;
    end else begin
      q_o <= d_i;
    end
  end
endmodule
