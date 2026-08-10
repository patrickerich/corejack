// SPDX-License-Identifier: Apache-2.0
//
module soc_axi_to_reg #(
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
  output soc_bus_pkg::soc_reg_req_t  m_reg_req_o,
  input  soc_bus_pkg::soc_reg_rsp_t  m_reg_rsp_i
);
  import axi_pkg::*;
  import soc_bus_pkg::*;

  typedef enum logic [2:0] {
    StateIdle,
    StateFirst,
    StateSecond,
    StateWriteResp,
    StateReadResp
  } state_e;

  state_e state_q;

  axi_aw_chan_t aw_q;
  axi_w_chan_t  w_q;
  axi_ar_chan_t ar_q;
  axi_b_chan_t  b_q;
  axi_r_chan_t  r_q;

  logic op_write_q;
  logic split_q;
  logic err_q;
  // Classified as illegal when the beat was captured (multi-beat burst or an
  // oversized beat). Distinct from err_q, which also accumulates errors the
  // register file reports mid-transaction: only the capture-time verdict
  // suppresses the access, so a split beat whose first half errors still
  // performs its second half exactly as before.
  logic illegal_q;
  // Round-robin tie-break between a pending read and a pending write so
  // neither starves. A write only competes once both AW and W are valid
  // (this adapter captures them together and has no collect state).
  // 1 => a read wins a simultaneous read/write tie.
  logic rr_prefer_read_q;
  logic rd_req;
  logic wr_req;
  logic arb_read;

  assign rd_req   = s_axi_req_i.ar_valid;
  assign wr_req   = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
  assign arb_read = rd_req && (!wr_req || rr_prefer_read_q);

  // An access step retires either on the register file's handshake or, for a
  // transaction suppressed as illegal, immediately - no request was issued, so
  // waiting on m_reg_rsp_i.ready would depend on how the target drives ready
  // with valid low.
  logic step_done;
  assign step_done = illegal_q || m_reg_rsp_i.ready;

  function automatic logic [31:0] active_addr(input logic second);
    logic [31:0] addr;
    addr = op_write_q ? aw_q.addr[31:0] : ar_q.addr[31:0];
    return addr + (second ? 32'd4 : 32'd0);
  endfunction

  function automatic reg_addr_t active_reg_addr(input logic second);
    logic [31:0] offset;
    offset = active_addr(second) - BaseAddr;
    // Register files decode word-exact addresses; sub-word accesses convey
    // their byte position through wstrb (writes) / lane extraction (reads).
    return {offset[RegAddrWidth-1:2], 2'b00};
  endfunction

  function automatic logic [31:0] active_wdata(input logic second);
    if (split_q) begin
      return second ? w_q.data[63:32] : w_q.data[31:0];
    end
    return aw_q.addr[2] ? w_q.data[63:32] : w_q.data[31:0];
  endfunction

  function automatic logic [3:0] active_wstrb(input logic second);
    if (split_q) begin
      return second ? w_q.strb[7:4] : w_q.strb[3:0];
    end
    return aw_q.addr[2] ? w_q.strb[7:4] : w_q.strb[3:0];
  endfunction

  always_comb begin
    s_axi_rsp_o = '0;
    m_reg_req_o = '{
      addr:  active_reg_addr(state_q == StateSecond),
      write: op_write_q,
      wdata: active_wdata(state_q == StateSecond),
      wstrb: active_wstrb(state_q == StateSecond),
      valid: 1'b0
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

      StateFirst,
      StateSecond: begin
        // A transaction already classified as illegal (multi-beat burst or an
        // oversized beat) must not reach the register file. Register reads can
        // have side effects - the PLIC claim register retires an interrupt on
        // read - so the SLVERR response has to be side-effect free.
        m_reg_req_o.valid = !illegal_q;
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
      err_q      <= 1'b0;
      illegal_q  <= 1'b0;
      rr_prefer_read_q <= 1'b1;
    end else begin
      unique case (state_q)
        StateIdle: begin
          if (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid && s_axi_req_i.w_valid) begin
            aw_q       <= s_axi_req_i.aw;
            w_q        <= s_axi_req_i.w;
            op_write_q <= 1'b1;
            // Split only 8-byte-aligned full-width beats: an unaligned size-3
            // beat addresses byte lanes [7:4] of the aligned window only, so it
            // is a single 32-bit access selected by addr[2] (AXI narrow-lane
            // rules; the debug SBA emits such beats for 32-bit accesses at
            // odd-word addresses).
            split_q    <= (s_axi_req_i.aw.size == axi_pkg::size_t'(3)) &&
                          !s_axi_req_i.aw.addr[2];
            err_q      <= (s_axi_req_i.aw.len != '0) || (s_axi_req_i.aw.size > axi_pkg::size_t'(3));
            illegal_q  <= (s_axi_req_i.aw.len != '0) || (s_axi_req_i.aw.size > axi_pkg::size_t'(3));
            rr_prefer_read_q <= 1'b1;  // serving a write; favor a read next
            state_q    <= StateFirst;
          end else if (s_axi_rsp_o.ar_ready && s_axi_req_i.ar_valid) begin
            ar_q       <= s_axi_req_i.ar;
            op_write_q <= 1'b0;
            split_q    <= (s_axi_req_i.ar.size == axi_pkg::size_t'(3)) &&
                          !s_axi_req_i.ar.addr[2];
            err_q      <= (s_axi_req_i.ar.len != '0) || (s_axi_req_i.ar.size > axi_pkg::size_t'(3));
            illegal_q  <= (s_axi_req_i.ar.len != '0) || (s_axi_req_i.ar.size > axi_pkg::size_t'(3));
            r_q.data   <= '0;
            rr_prefer_read_q <= 1'b0;  // just served a read; favor a write next
            state_q    <= StateFirst;
          end
        end

        StateFirst: begin
          if (step_done) begin
            err_q <= err_q | m_reg_rsp_i.error;
            if (!op_write_q) begin
              if (split_q) begin
                r_q.data[31:0] <= m_reg_rsp_i.rdata;
              end else if (ar_q.addr[2]) begin
                r_q.data[63:32] <= m_reg_rsp_i.rdata;
              end else begin
                r_q.data[31:0] <= m_reg_rsp_i.rdata;
              end
            end

            if (split_q) begin
              state_q <= StateSecond;
            end else if (op_write_q) begin
              b_q.id   <= aw_q.id;
              b_q.resp <= (err_q | m_reg_rsp_i.error) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
              b_q.user <= '0;
              state_q  <= StateWriteResp;
            end else begin
              r_q.id   <= ar_q.id;
              r_q.resp <= (err_q | m_reg_rsp_i.error) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
              r_q.last <= 1'b1;
              r_q.user <= '0;
              state_q  <= StateReadResp;
            end
          end
        end

        StateSecond: begin
          if (step_done) begin
            err_q <= err_q | m_reg_rsp_i.error;
            if (!op_write_q) begin
              r_q.data[63:32] <= m_reg_rsp_i.rdata;
            end

            if (op_write_q) begin
              b_q.id   <= aw_q.id;
              b_q.resp <= (err_q | m_reg_rsp_i.error) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
              b_q.user <= '0;
              state_q  <= StateWriteResp;
            end else begin
              r_q.id   <= ar_q.id;
              r_q.resp <= (err_q | m_reg_rsp_i.error) ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
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
