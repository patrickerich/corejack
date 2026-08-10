// SPDX-License-Identifier: Apache-2.0
//
// AXI4 (single-beat) to banked-memory bridge for soc_mem_ss.
//
// The read and write directions are independent engines, each driving its OWN
// soc_mem_ss init port. Because soc_mem_ss is a banked memory (multiple
// single-port slices behind a per-bank round-robin arbiter), a read and a write
// to different banks are serviced in the same cycle; a same-bank conflict is
// resolved by the bank arbiter (one side stalls one cycle via gnt). This
// exploits AXI's independent read/write channels and the memory's bank
// parallelism instead of serializing the two through one FSM/port.
//
// Each engine keeps one transaction in flight on its own init port. That is a
// property of this bridge, not of soc_mem_ss: the memory ports are themselves
// multi-outstanding (EgressDepth), so these two engines - and therefore the
// crossbar's RAM legs - are what caps fabric-routed RAM traffic below the
// per-port rate the memory can sustain. Splitting the engines also removes the
// former lone-AW deadlock workaround: the read engine never waits on the write
// engine, so a read-to-write coupled initiator (e.g. the iDMA doing an in-RAM
// memcpy) cannot deadlock.
module soc_axi_to_mem
  import axi_pkg::*;
  import soc_bus_pkg::*;
#(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = soc_bus_pkg::AxiDataWidth,
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

  input  axi_req_t  s_axi_req_i,
  output axi_resp_t s_axi_rsp_o,

  // Read engine init port (mem_rd_we_o is always 0).
  output logic                   mem_rd_req_o,
  output logic                   mem_rd_we_o,
  output logic [AddrWidth-1:0]   mem_rd_addr_o,
  output logic [DataWidth-1:0]   mem_rd_wdata_o,
  output logic [DataWidth/8-1:0] mem_rd_be_o,
  input  logic                   mem_rd_gnt_i,
  input  logic                   mem_rd_rvalid_i,
  output logic                   mem_rd_rready_o,
  input  logic [DataWidth-1:0]   mem_rd_rdata_i,
  input  logic                   mem_rd_err_i,

  // Write engine init port (mem_wr_we_o is always 1; no read data needed).
  output logic                   mem_wr_req_o,
  output logic                   mem_wr_we_o,
  output logic [AddrWidth-1:0]   mem_wr_addr_o,
  output logic [DataWidth-1:0]   mem_wr_wdata_o,
  output logic [DataWidth/8-1:0] mem_wr_be_o,
  input  logic                   mem_wr_gnt_i,
  input  logic                   mem_wr_rvalid_i,
  output logic                   mem_wr_rready_o,
  input  logic                   mem_wr_err_i
);
  // ---------------------------------------------------------------------------
  // Read engine: AR/R channels -> read init port.
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {RdIdle, RdMem, RdWait, RdResp} rd_state_e;
  rd_state_e    rd_state_q;
  axi_ar_chan_t ar_q;
  axi_r_chan_t  r_q;

  logic rd_ar_ready;
  logic rd_r_valid;

  always_comb begin
    rd_ar_ready     = 1'b0;
    rd_r_valid      = 1'b0;
    mem_rd_req_o    = 1'b0;
    mem_rd_we_o     = 1'b0;
    mem_rd_addr_o   = '0;
    mem_rd_wdata_o  = '0;
    mem_rd_be_o     = '0;
    mem_rd_rready_o = 1'b0;

    unique case (rd_state_q)
      RdIdle: begin
        rd_ar_ready = 1'b1;
      end
      RdMem: begin
        mem_rd_req_o    = 1'b1;
        mem_rd_addr_o   = AddrWidth'(ar_q.addr);
        mem_rd_be_o     = '1;
        mem_rd_rready_o = 1'b1;
      end
      RdWait: begin
        mem_rd_rready_o = 1'b1;
      end
      RdResp: begin
        rd_r_valid = 1'b1;
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rd_state_q <= RdIdle;
      ar_q       <= '0;
      r_q        <= '0;
    end else begin
      unique case (rd_state_q)
        RdIdle: begin
          if (rd_ar_ready && s_axi_req_i.ar_valid) begin
            ar_q       <= s_axi_req_i.ar;
            rd_state_q <= RdMem;
          end
        end
        RdMem: begin
          if (mem_rd_req_o && mem_rd_gnt_i) begin
            rd_state_q <= RdWait;
          end
        end
        RdWait: begin
          if (mem_rd_rvalid_i) begin
            r_q.id   <= ar_q.id;
            r_q.data <= DataWidth'(mem_rd_rdata_i);
            r_q.resp <= mem_rd_err_i ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
            r_q.last <= 1'b1;
            r_q.user <= '0;
            rd_state_q <= RdResp;
          end
        end
        RdResp: begin
          if (s_axi_req_i.r_ready) begin
            rd_state_q <= RdIdle;
          end
        end
        default: begin
          rd_state_q <= RdIdle;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Write engine: AW/W/B channels -> write init port. A write competes only
  // once both AW and W are valid (committing on a lone AW is unnecessary and
  // was the old deadlock source); the read engine is independent either way.
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {WrIdle, WrMem, WrWait, WrResp} wr_state_e;
  wr_state_e    wr_state_q;
  axi_aw_chan_t aw_q;
  axi_w_chan_t  w_q;
  axi_b_chan_t  b_q;

  logic wr_aw_ready;
  logic wr_w_ready;
  logic wr_b_valid;
  logic wr_fire;

  assign wr_fire = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;

  always_comb begin
    wr_aw_ready     = 1'b0;
    wr_w_ready      = 1'b0;
    wr_b_valid      = 1'b0;
    mem_wr_req_o    = 1'b0;
    mem_wr_we_o     = 1'b0;
    mem_wr_addr_o   = '0;
    mem_wr_wdata_o  = '0;
    mem_wr_be_o     = '0;
    mem_wr_rready_o = 1'b0;

    unique case (wr_state_q)
      WrIdle: begin
        wr_aw_ready = wr_fire;
        wr_w_ready  = wr_fire;
      end
      WrMem: begin
        mem_wr_req_o   = 1'b1;
        mem_wr_we_o    = 1'b1;
        mem_wr_addr_o  = AddrWidth'(aw_q.addr);
        mem_wr_wdata_o = DataWidth'(w_q.data);
        mem_wr_be_o    = w_q.strb[DataWidth/8-1:0];
      end
      WrWait: begin
        mem_wr_rready_o = 1'b1;
      end
      WrResp: begin
        wr_b_valid = 1'b1;
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_state_q <= WrIdle;
      aw_q       <= '0;
      w_q        <= '0;
      b_q        <= '0;
    end else begin
      unique case (wr_state_q)
        WrIdle: begin
          if (wr_aw_ready && s_axi_req_i.aw_valid &&
              wr_w_ready && s_axi_req_i.w_valid) begin
            aw_q       <= s_axi_req_i.aw;
            w_q        <= s_axi_req_i.w;
            wr_state_q <= WrMem;
          end
        end
        WrMem: begin
          if (mem_wr_req_o && mem_wr_gnt_i) begin
            wr_state_q <= WrWait;
          end
        end
        WrWait: begin
          if (mem_wr_rvalid_i) begin
            b_q.id   <= aw_q.id;
            b_q.resp <= mem_wr_err_i ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
            b_q.user <= '0;
            wr_state_q <= WrResp;
          end
        end
        WrResp: begin
          if (s_axi_req_i.b_ready) begin
            wr_state_q <= WrIdle;
          end
        end
        default: begin
          wr_state_q <= WrIdle;
        end
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // Response channel merge: the two engines drive disjoint AXI response fields.
  // ---------------------------------------------------------------------------
  always_comb begin
    s_axi_rsp_o          = '0;
    s_axi_rsp_o.ar_ready = rd_ar_ready;
    s_axi_rsp_o.r_valid  = rd_r_valid;
    s_axi_rsp_o.r        = r_q;
    s_axi_rsp_o.aw_ready = wr_aw_ready;
    s_axi_rsp_o.w_ready  = wr_w_ready;
    s_axi_rsp_o.b_valid  = wr_b_valid;
    s_axi_rsp_o.b        = b_q;
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (rd_state_q == RdMem) begin
        assert (ar_q.len == '0);
      end
      if (wr_state_q == WrMem) begin
        assert (aw_q.len == '0);
        assert (w_q.last);
      end
    end
  end
`endif
endmodule
