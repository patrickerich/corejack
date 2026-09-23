// SPDX-License-Identifier: Apache-2.0
//
// Request FIFO in front of a soc_mem_bank SRAM slice.
//
// Behaves like common_cells fifo_v3 with FALL_THROUGH = 0 (registered head, and
// a push is refused while full even if a pop happens in the same cycle), but
// with a reset style chosen for what its outputs drive: the head entry is the
// SRAM address, write enable and write data, and empty_o gates the SRAM enable.
// fifo_v3 resets its storage and pointers asynchronously, so asserting reset
// moves those SRAM pins mid-cycle, where static timing does not look, and can
// corrupt a write in flight (Vivado REQP-1839 on 7-series block RAM; the same
// hazard applies to an ASIC SRAM macro). Here the storage has no reset at all
// and the pointers and count reset synchronously, so the SRAM pins only change
// on a clock edge. The clock must run for at least one edge while rst_ni is
// held low.
module soc_mem_bank_fifo #(
  parameter int unsigned DataWidth = 1,
  parameter int unsigned Depth     = 2
) (
  input  logic                 clk_i,
  // Deliberate exception to the rst_ni convention: sampled synchronously.
  input  logic                 rst_ni,
  input  logic                 push_i,
  input  logic [DataWidth-1:0] data_i,
  output logic                 full_o,
  input  logic                 pop_i,
  output logic [DataWidth-1:0] data_o,
  output logic                 empty_o
);
  localparam int unsigned PtrWidth = (Depth > 1) ? $clog2(Depth) : 1;
  localparam int unsigned CntWidth = $clog2(Depth + 1);

  if (Depth < 1) begin : gen_validate_depth
    $fatal(1, "soc_mem_bank_fifo: Depth must be at least 1");
  end

  logic [DataWidth-1:0] mem_q [Depth];
  logic [PtrWidth-1:0]  wr_ptr_q, rd_ptr_q;
  logic [CntWidth-1:0]  count_q;
  logic                 push, pop;

  assign full_o  = (count_q == CntWidth'(Depth));
  assign empty_o = (count_q == '0);
  assign push    = push_i & ~full_o;
  assign pop     = pop_i & ~empty_o;
  assign data_o  = mem_q[rd_ptr_q];

  function automatic logic [PtrWidth-1:0] next_ptr(logic [PtrWidth-1:0] ptr);
    return (ptr == PtrWidth'(Depth - 1)) ? '0 : ptr + PtrWidth'(1);
  endfunction

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
      count_q  <= '0;
    end else begin
      if (push) begin
        wr_ptr_q <= next_ptr(wr_ptr_q);
      end
      if (pop) begin
        rd_ptr_q <= next_ptr(rd_ptr_q);
      end
      count_q <= count_q + CntWidth'(push) - CntWidth'(pop);
    end
  end

  // No reset: an entry is only read after it has been written.
  always_ff @(posedge clk_i) begin
    if (push) begin
      mem_q[wr_ptr_q] <= data_i;
    end
  end

`ifndef SYNTHESIS
  // The same misuse checks fifo_v3 carries.
  assert property (@(posedge clk_i) disable iff (!rst_ni) !(push_i && full_o))
    else $error("soc_mem_bank_fifo: push while full");
  assert property (@(posedge clk_i) disable iff (!rst_ni) !(pop_i && empty_o))
    else $error("soc_mem_bank_fifo: pop while empty");
`endif
endmodule
