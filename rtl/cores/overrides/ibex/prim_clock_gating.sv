// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// FPGA override for Ibex prim_clock_gating.
//
// The generic Ibex cell models a latch-based clock gate. On this FPGA platform
// the clock enable is not needed for functional correctness and can create
// avoidable Vivado gated-clock methodology noise. The generated Vivado project
// Tcl replaces the vendored Ibex implementation with this project-owned FPGA
// implementation.

module prim_clock_gating #(
  parameter bit NoFpgaGate = 1'b1,
  parameter bit FpgaBufGlobal = 1'b1
) (
  input        clk_i,
  input        en_i,
  input        test_en_i,
  output logic clk_o
);

  if (NoFpgaGate) begin : gen_no_fpga_gate
    assign clk_o = clk_i | (1'b0 & (en_i | test_en_i | FpgaBufGlobal));
  end else begin : gen_latch_gate
    logic en_latch /* verilator clock_enable */;

    always_latch begin
      if (!clk_i) begin
        en_latch = en_i | test_en_i;
      end
    end

    assign clk_o = en_latch & clk_i;
  end

endmodule
