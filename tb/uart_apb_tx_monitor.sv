// SPDX-License-Identifier: Apache-2.0
//
module uart_apb_tx_monitor #(
  parameter type apb_req_t = logic
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  apb_req_t uart_apb_req_i,
  output logic tx_valid_o,
  output logic [7:0] tx_data_o
);
  localparam logic [31:0] UartThrOffset = 32'h0000_0000;
  localparam logic [31:0] UartLcrOffset = 32'h0000_000c;
  localparam logic [7:0] UartLcrDlabBit = 8'h80;

  logic [7:0] uart_lcr_q;
  logic       uart_write_level_q;
  logic       uart_write_level;
  logic [7:0] uart_write_data;

  always_comb begin
    uart_write_data = uart_apb_req_i.pwdata[7:0];
    unique case (uart_apb_req_i.pstrb)
      4'b0010: uart_write_data = uart_apb_req_i.pwdata[15:8];
      4'b0100: uart_write_data = uart_apb_req_i.pwdata[23:16];
      4'b1000: uart_write_data = uart_apb_req_i.pwdata[31:24];
      default: uart_write_data = uart_apb_req_i.pwdata[7:0];
    endcase
  end

  always_comb begin
    uart_write_level = uart_apb_req_i.psel && uart_apb_req_i.penable && uart_apb_req_i.pwrite;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uart_lcr_q         <= 8'h03;
      uart_write_level_q <= 1'b0;
      tx_valid_o         <= 1'b0;
      tx_data_o          <= '0;
    end else begin
      tx_valid_o <= 1'b0;
      tx_data_o  <= '0;

      if (uart_write_level && !uart_write_level_q) begin
        if (uart_apb_req_i.paddr == UartLcrOffset) begin
          uart_lcr_q <= uart_write_data;
        end else if ((uart_apb_req_i.paddr == UartThrOffset) &&
                     ((uart_lcr_q & UartLcrDlabBit) == 8'h00) &&
                     (uart_write_data != 8'h0d)) begin
          tx_valid_o <= 1'b1;
          tx_data_o  <= uart_write_data;
        end
      end

      uart_write_level_q <= uart_write_level;
    end
  end
endmodule
