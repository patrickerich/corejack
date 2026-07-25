// SPDX-License-Identifier: Apache-2.0
//
module uart_sram_loader_dut (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        enable_i,
  input  logic        uart_rx_i,
  output logic        uart_tx_o,
  output logic        active_o,
  output logic        done_o,
  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic [31:0] mem_addr_o,
  output logic [63:0] mem_wdata_o,
  output logic [7:0]  mem_be_o,
  input  logic        mem_gnt_i,
  input  logic        mem_rvalid_i,
  output logic        mem_rready_o,
  input  logic        mem_err_i
);
  soc_uart_sram_loader #(
    .ClockHz   (1_000_000),
    .Baud      (100_000),
    .AddrWidth (32),
    .DataWidth (64)
  ) i_loader (
    .clk_i,
    .rst_ni,
    .enable_i,
    .uart_rx_i,
    .uart_tx_o,
    .active_o,
    .done_o,
    .mem_req_o,
    .mem_we_o,
    .mem_addr_o,
    .mem_wdata_o,
    .mem_be_o,
    .mem_gnt_i,
    .mem_rvalid_i,
    .mem_rready_o,
    .mem_err_i
  );
endmodule
