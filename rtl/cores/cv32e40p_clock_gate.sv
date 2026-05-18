module cv32e40p_clock_gate (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);
  // FPGA-friendly placeholder clock gate. The core still observes sleep state,
  // but the local clock is left ungated until a board/library-specific gate is
  // selected.
  assign clk_o = clk_i;

  logic unused_en;
  assign unused_en = en_i ^ scan_cg_en_i;
endmodule
