// SPDX-License-Identifier: Apache-2.0
//
module soc_uart_sram_loader #(
  parameter int unsigned ClockHz = 25_000_000,
  parameter int unsigned Baud = 115_200,
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 64
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,
  input  logic                     enable_i,
  input  logic                     uart_rx_i,
  output logic                     uart_tx_o,
  output logic                     active_o,
  output logic                     done_o,
  output logic                     mem_req_o,
  output logic                     mem_we_o,
  output logic [AddrWidth-1:0]     mem_addr_o,
  output logic [DataWidth-1:0]     mem_wdata_o,
  output logic [DataWidth/8-1:0]   mem_be_o,
  input  logic                     mem_gnt_i,
  input  logic                     mem_rvalid_i,
  output logic                     mem_rready_o,
  input  logic                     mem_err_i
);
  localparam int unsigned DataBytes = DataWidth / 8;
  localparam int unsigned LaneWidth = (DataBytes > 1) ? $clog2(DataBytes) : 1;
  localparam int unsigned BaudDivRaw = ClockHz / Baud;
  localparam int unsigned BaudDiv = (BaudDivRaw > 0) ? BaudDivRaw : 1;
  localparam int unsigned RxFirstSampleDiv = BaudDiv + (BaudDiv / 2);
  localparam int unsigned BaudCntWidth = (RxFirstSampleDiv > 1) ? $clog2(RxFirstSampleDiv) : 1;

  localparam logic [7:0] CmdPing = 8'h3f; // '?'
  localparam logic [7:0] CmdWrite = 8'h57; // 'W'
  localparam logic [7:0] CmdGo = 8'h47; // 'G'
  localparam logic [7:0] RespAck = 8'h06;
  localparam logic [7:0] RespNak = 8'h15;

  typedef enum logic [3:0] {
    StateIdle,
    StateAddr0,
    StateAddr1,
    StateAddr2,
    StateAddr3,
    StateLen0,
    StateLen1,
    StateData,
    StateMemReq,
    StateMemRsp,
    StateResp,
    StateRelease
  } state_e;

  state_e state_q;
  logic active_q;
  logic done_q;

  logic rx_meta_q;
  logic rx_sync_q;
  logic rx_busy_q;
  logic [BaudCntWidth-1:0] rx_baud_cnt_q;
  logic [3:0] rx_bit_cnt_q;
  logic [7:0] rx_shift_q;
  logic [7:0] rx_data_q;
  logic rx_valid_q;

  logic tx_busy_q;
  logic [BaudCntWidth-1:0] tx_baud_cnt_q;
  logic [3:0] tx_bit_cnt_q;
  logic [9:0] tx_shift_q;
  logic tx_start;
  logic tx_start_q;
  logic [7:0] tx_data;

  logic [31:0] addr_q;
  logic [15:0] len_q;
  logic [7:0] byte_q;
  logic [7:0] resp_q;
  logic pending_release_q;
  logic release_seen_busy_q;
  logic mem_req_q;
  logic mem_error_q;

  assign active_o = active_q;
  assign done_o = done_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_meta_q     <= 1'b1;
      rx_sync_q     <= 1'b1;
      rx_busy_q     <= 1'b0;
      rx_baud_cnt_q <= '0;
      rx_bit_cnt_q  <= '0;
      rx_shift_q    <= '0;
      rx_data_q     <= '0;
      rx_valid_q    <= 1'b0;
    end else begin
      rx_meta_q  <= uart_rx_i;
      rx_sync_q  <= rx_meta_q;
      rx_valid_q <= 1'b0;

      if (!active_q) begin
        rx_busy_q <= 1'b0;
      end else if (!rx_busy_q) begin
        if (!rx_sync_q) begin
          rx_busy_q     <= 1'b1;
          rx_baud_cnt_q <= BaudCntWidth'(RxFirstSampleDiv - 1);
          rx_bit_cnt_q  <= '0;
        end
      end else if (rx_baud_cnt_q != '0) begin
        rx_baud_cnt_q <= rx_baud_cnt_q - 1'b1;
      end else begin
        rx_baud_cnt_q <= BaudCntWidth'(BaudDiv - 1);
        if (rx_bit_cnt_q < 8) begin
          rx_shift_q[rx_bit_cnt_q] <= rx_sync_q;
          rx_bit_cnt_q <= rx_bit_cnt_q + 1'b1;
        end else begin
          rx_busy_q <= 1'b0;
          if (rx_sync_q) begin
            rx_data_q  <= rx_shift_q;
            rx_valid_q <= 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_busy_q     <= 1'b0;
      tx_baud_cnt_q <= '0;
      tx_bit_cnt_q  <= '0;
      tx_shift_q    <= '1;
      uart_tx_o     <= 1'b1;
    end else if (!tx_busy_q) begin
      uart_tx_o <= 1'b1;
      if (tx_start) begin
        tx_busy_q     <= 1'b1;
        tx_baud_cnt_q <= BaudCntWidth'(BaudDiv - 1);
        tx_bit_cnt_q  <= '0;
        tx_shift_q    <= {1'b1, tx_data, 1'b0};
        uart_tx_o     <= 1'b0;
      end
    end else if (tx_baud_cnt_q != '0) begin
      tx_baud_cnt_q <= tx_baud_cnt_q - 1'b1;
    end else begin
      tx_baud_cnt_q <= BaudCntWidth'(BaudDiv - 1);
      tx_bit_cnt_q  <= tx_bit_cnt_q + 1'b1;
      tx_shift_q    <= {1'b1, tx_shift_q[9:1]};
      uart_tx_o     <= tx_shift_q[1];
      if (tx_bit_cnt_q == 9) begin
        tx_busy_q <= 1'b0;
      end
    end
  end

  assign tx_start = tx_start_q;
  assign tx_data = resp_q;

  always_comb begin
    mem_req_o = mem_req_q;
    mem_we_o = 1'b1;
    mem_addr_o = addr_q;
    mem_wdata_o = '0;
    mem_be_o = '0;
    mem_rready_o = 1'b1;

    if (state_q == StateMemReq || state_q == StateMemRsp) begin
      for (int unsigned lane = 0; lane < DataBytes; lane++) begin
        if (addr_q[LaneWidth-1:0] == LaneWidth'(lane)) begin
          mem_wdata_o[8 * lane +: 8] = byte_q;
          mem_be_o[lane] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q           <= StateIdle;
      active_q          <= 1'b0;
      done_q            <= 1'b0;
      addr_q            <= '0;
      len_q             <= '0;
      byte_q            <= '0;
      resp_q            <= RespAck;
      pending_release_q <= 1'b0;
      release_seen_busy_q <= 1'b0;
      mem_req_q         <= 1'b0;
      mem_error_q       <= 1'b0;
      tx_start_q        <= 1'b0;
    end else begin
      mem_req_q <= 1'b0;
      tx_start_q <= 1'b0;

      if (!enable_i) begin
        state_q           <= StateIdle;
        active_q          <= 1'b0;
        done_q            <= 1'b0;
        pending_release_q <= 1'b0;
        release_seen_busy_q <= 1'b0;
        mem_error_q       <= 1'b0;
      end else begin
        if (!active_q && !done_q) begin
          active_q <= 1'b1;
        end

        unique case (state_q)
          StateIdle: begin
            pending_release_q <= 1'b0;
            mem_error_q       <= 1'b0;
            if (active_q && rx_valid_q) begin
              unique case (rx_data_q)
                CmdPing: begin
                  resp_q  <= RespAck;
                  state_q <= StateResp;
                end
                CmdGo: begin
                  resp_q            <= RespAck;
                  pending_release_q <= 1'b1;
                  state_q           <= StateResp;
                end
                CmdWrite: begin
                  state_q <= StateAddr0;
                end
                default: begin
                  resp_q  <= RespNak;
                  state_q <= StateResp;
                end
              endcase
            end
          end

          StateAddr0: if (rx_valid_q) begin
            addr_q[7:0] <= rx_data_q;
            state_q <= StateAddr1;
          end

          StateAddr1: if (rx_valid_q) begin
            addr_q[15:8] <= rx_data_q;
            state_q <= StateAddr2;
          end

          StateAddr2: if (rx_valid_q) begin
            addr_q[23:16] <= rx_data_q;
            state_q <= StateAddr3;
          end

          StateAddr3: if (rx_valid_q) begin
            addr_q[31:24] <= rx_data_q;
            state_q <= StateLen0;
          end

          StateLen0: if (rx_valid_q) begin
            len_q[7:0] <= rx_data_q;
            state_q <= StateLen1;
          end

          StateLen1: if (rx_valid_q) begin
            len_q[15:8] <= rx_data_q;
            if ({rx_data_q, len_q[7:0]} == 16'h0000) begin
              resp_q  <= RespAck;
              state_q <= StateResp;
            end else begin
              state_q <= StateData;
            end
          end

          StateData: begin
            if (rx_valid_q) begin
              byte_q    <= rx_data_q;
              mem_req_q <= 1'b1;
              state_q   <= StateMemReq;
            end
          end

          StateMemReq: begin
            mem_req_q <= !mem_gnt_i;
            if (mem_gnt_i) begin
              state_q <= StateMemRsp;
            end
          end

          StateMemRsp: begin
            if (mem_rvalid_i) begin
              mem_error_q <= mem_error_q | mem_err_i;
              addr_q      <= addr_q + 32'd1;
              len_q       <= len_q - 16'd1;
              if (len_q == 16'd1) begin
                resp_q  <= (mem_error_q | mem_err_i) ? RespNak : RespAck;
                state_q <= StateResp;
              end else begin
                state_q <= StateData;
              end
            end
          end

          StateResp: begin
            if (!tx_busy_q) begin
              release_seen_busy_q <= 1'b0;
              tx_start_q <= 1'b1;
              state_q    <= pending_release_q ? StateRelease : StateIdle;
            end
          end

          StateRelease: begin
            release_seen_busy_q <= release_seen_busy_q | tx_busy_q;
            if (release_seen_busy_q && !tx_busy_q) begin
              active_q <= 1'b0;
              done_q   <= 1'b1;
              state_q  <= StateIdle;
            end
          end

          default: begin
            state_q <= StateIdle;
          end
        endcase
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    assert (DataWidth == 64)
      else $fatal(1, "soc_uart_sram_loader currently expects a 64-bit memory path");
    assert (DataBytes > 1) else $fatal(1, "soc_uart_sram_loader requires byte-lane addressing");
  end
`endif
endmodule
