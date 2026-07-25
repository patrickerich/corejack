// SPDX-License-Identifier: Apache-2.0
//
module soc_axi_to_apb #(
  parameter logic [31:0] BaseAddr = 32'h0,
  // AXI slave-port types. Default to the platform initiator-side types; the
  // platform overrides these with the wider master-side types behind the xbar.
  parameter type axi_req_t     = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_resp_t    = soc_bus_pkg::soc_axi_resp_t,
  parameter type axi_aw_chan_t = soc_bus_pkg::soc_axi_aw_chan_t,
  parameter type axi_w_chan_t  = soc_bus_pkg::soc_axi_w_chan_t,
  parameter type axi_ar_chan_t = soc_bus_pkg::soc_axi_ar_chan_t,
  parameter type axi_b_chan_t  = soc_bus_pkg::soc_axi_b_chan_t,
  parameter type axi_r_chan_t  = soc_bus_pkg::soc_axi_r_chan_t
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  axi_req_t                   s_axi_req_i,
  output axi_resp_t                  s_axi_rsp_o,
  output soc_bus_pkg::soc_apb_req_t  m_apb_req_o,
  input  soc_bus_pkg::soc_apb_resp_t m_apb_rsp_i
);
  import axi_pkg::*;

  typedef enum logic [2:0] {
    StateIdle,
    StateSetup,
    StateAccess,
    StateWriteResp,
    StateReadResp
  } state_e;

  state_e state_q;
  axi_aw_chan_t aw_q;
  axi_w_chan_t  w_q;
  axi_ar_chan_t ar_q;
  axi_b_chan_t  b_q;
  axi_r_chan_t  r_q;
  logic         op_write_q;
  // A full-width (size 3) beat at an 8-byte-aligned address covers both 32-bit
  // halves and is split into two APB transfers (low word first), matching
  // soc_axi_to_reg. An unaligned size-3 beat only addresses byte lanes [7:4],
  // so it takes the single-transfer path selected by addr[2].
  logic         split_q;
  logic         second_q;
  logic         err_q;
  // Round-robin tie-break between a pending read and a pending write so
  // neither starves. A write only competes once both AW and W are valid
  // (this adapter captures them together and has no collect state).
  // 1 => a read wins a simultaneous read/write tie.
  logic         rr_prefer_read_q;
  logic         rd_req;
  logic         wr_req;
  logic         arb_read;

  assign rd_req   = s_axi_req_i.ar_valid;
  assign wr_req   = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
  assign arb_read = rd_req && (!wr_req || rr_prefer_read_q);

  function automatic logic [31:0] active_addr(input logic second);
    logic [31:0] addr;
    addr = op_write_q ? aw_q.addr[31:0] : ar_q.addr[31:0];
    return addr + (second ? 32'd4 : 32'd0);
  endfunction

  // Which 32-bit half of the 64-bit AXI data bus the current APB transfer uses.
  function automatic logic active_high_lane(input logic second);
    return split_q ? second : (op_write_q ? aw_q.addr[2] : ar_q.addr[2]);
  endfunction

  function automatic logic [31:0] active_wdata(input logic second);
    return active_high_lane(second) ? w_q.data[63:32] : w_q.data[31:0];
  endfunction

  function automatic logic [3:0] active_strb(input logic second);
    return active_high_lane(second) ? w_q.strb[7:4] : w_q.strb[3:0];
  endfunction

  always_comb begin
    s_axi_rsp_o = '0;
    m_apb_req_o = '{
      paddr:   active_addr(second_q) - BaseAddr,
      pprot:   '0,
      psel:    1'b0,
      penable: 1'b0,
      pwrite:  op_write_q,
      pwdata:  active_wdata(second_q),
      // APB4 requires PSTRB to be driven low during read transfers.
      pstrb:   op_write_q ? active_strb(second_q) : 4'h0
    };

    unique case (state_q)
      StateIdle: begin
        // Serve exactly one side, chosen by arb_read. Gating each channel on
        // the other's valid would leave both readies low forever when the
        // crossbar presents a read and a write in the same cycle - see the
        // identical fix in soc_axi_to_mem.
        if (arb_read) begin
          s_axi_rsp_o.ar_ready = 1'b1;
        end else begin
          s_axi_rsp_o.aw_ready = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
          s_axi_rsp_o.w_ready  = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
        end
      end

      // An invalid beat (burst, or size > 3) performs no APB transfer at all
      // and is answered with SLVERR from StateSetup.
      StateSetup: begin
        m_apb_req_o.psel = !err_q;
      end

      StateAccess: begin
        m_apb_req_o.psel    = 1'b1;
        m_apb_req_o.penable = 1'b1;
      end

      StateWriteResp: begin
        s_axi_rsp_o.b_valid = 1'b1;
        s_axi_rsp_o.b       = b_q;
      end

      StateReadResp: begin
        s_axi_rsp_o.r_valid = 1'b1;
        s_axi_rsp_o.r       = r_q;
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= StateIdle;
      aw_q       <= '0;
      w_q        <= '0;
      ar_q       <= '0;
      b_q        <= '0;
      r_q        <= '0;
      op_write_q <= 1'b0;
      split_q    <= 1'b0;
      second_q   <= 1'b0;
      err_q      <= 1'b0;
      rr_prefer_read_q <= 1'b1;
    end else begin
      unique case (state_q)
        StateIdle: begin
          second_q <= 1'b0;
          if (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid && s_axi_req_i.w_valid) begin
            aw_q       <= s_axi_req_i.aw;
            w_q        <= s_axi_req_i.w;
            op_write_q <= 1'b1;
            split_q    <= (s_axi_req_i.aw.size == axi_pkg::size_t'(3)) &&
                          !s_axi_req_i.aw.addr[2];
            err_q      <= (s_axi_req_i.aw.len != '0) ||
                          (s_axi_req_i.aw.size > axi_pkg::size_t'(3));
            rr_prefer_read_q <= 1'b1;  // serving a write; favor a read next
            state_q    <= StateSetup;
          end else if (s_axi_rsp_o.ar_ready && s_axi_req_i.ar_valid) begin
            ar_q       <= s_axi_req_i.ar;
            op_write_q <= 1'b0;
            split_q    <= (s_axi_req_i.ar.size == axi_pkg::size_t'(3)) &&
                          !s_axi_req_i.ar.addr[2];
            err_q      <= (s_axi_req_i.ar.len != '0) ||
                          (s_axi_req_i.ar.size > axi_pkg::size_t'(3));
            r_q.data   <= '0;
            rr_prefer_read_q <= 1'b0;  // just served a read; favor a write next
            state_q    <= StateSetup;
          end
        end

        StateSetup: begin
          if (err_q) begin
            if (op_write_q) begin
              b_q.id   <= aw_q.id;
              b_q.resp <= axi_pkg::RESP_SLVERR;
              b_q.user <= '0;
              state_q  <= StateWriteResp;
            end else begin
              r_q.id   <= ar_q.id;
              r_q.resp <= axi_pkg::RESP_SLVERR;
              r_q.last <= 1'b1;
              r_q.user <= '0;
              state_q  <= StateReadResp;
            end
          end else begin
            state_q <= StateAccess;
          end
        end

        StateAccess: begin
          if (m_apb_rsp_i.pready) begin
            err_q <= err_q | m_apb_rsp_i.pslverr;
            if (!op_write_q) begin
              if (active_high_lane(second_q)) begin
                r_q.data[63:32] <= m_apb_rsp_i.prdata;
              end else begin
                r_q.data[31:0] <= m_apb_rsp_i.prdata;
              end
            end

            if (split_q && !second_q) begin
              second_q <= 1'b1;
              state_q  <= StateSetup;
            end else if (op_write_q) begin
              b_q.id   <= aw_q.id;
              b_q.resp <= (err_q | m_apb_rsp_i.pslverr) ? axi_pkg::RESP_SLVERR
                                                        : axi_pkg::RESP_OKAY;
              b_q.user <= '0;
              state_q  <= StateWriteResp;
            end else begin
              r_q.id   <= ar_q.id;
              r_q.resp <= (err_q | m_apb_rsp_i.pslverr) ? axi_pkg::RESP_SLVERR
                                                        : axi_pkg::RESP_OKAY;
              r_q.last <= 1'b1;
              r_q.user <= '0;
              state_q  <= StateReadResp;
            end
          end
        end

        StateWriteResp: begin
          if (s_axi_req_i.b_ready) begin
            state_q <= StateIdle;
          end
        end

        StateReadResp: begin
          if (s_axi_req_i.r_ready) begin
            state_q <= StateIdle;
          end
        end

        default: begin
          state_q <= StateIdle;
        end
      endcase
    end
  end
endmodule
