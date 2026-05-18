// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
module cvw_counter #(
  parameter int unsigned WIDTH = 8
) (
  input  logic             clk,
  input  logic             reset,
  input  logic             en,
  output logic [WIDTH-1:0] q
);
  logic [WIDTH-1:0] qnext;

  assign qnext = q + WIDTH'(1);

  flopenr #(WIDTH) i_cntrflop (
    .clk,
    .reset,
    .en,
    .d (qnext),
    .q
  );
endmodule
