// SPDX-License-Identifier: Apache-2.0
//
module soc_obi_to_axi
  import axi_pkg::*;
  import soc_bus_pkg::*;
#(
  parameter int unsigned ObiAddrWidth = 32,
  parameter int unsigned ObiDataWidth = 32,
  parameter soc_bus_pkg::axi_id_t AxiId = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [ObiAddrWidth-1:0]       s_addr_i,
  input  logic [ObiDataWidth-1:0]       s_wdata_i,
  input  logic [ObiDataWidth/8-1:0]     s_be_i,
  input  logic                          s_we_i,
  input  logic                          s_req_i,
  output logic                          s_gnt_o,
  output logic                          s_rvalid_o,
  input  logic                          s_rready_i,
  output logic [ObiDataWidth-1:0]       s_rdata_o,
  output logic                          s_err_o,

  output soc_bus_pkg::soc_axi_req_t     m_axi_req_o,
  input  soc_bus_pkg::soc_axi_resp_t    m_axi_rsp_i
);
  // The fabric widths come from soc_bus_pkg (wildcard import above); they are
  // deliberately not module parameters so they cannot shadow or diverge from
  // the package-typed AXI port structs.
  localparam int unsigned ObiBytes = ObiDataWidth / 8;
  localparam int unsigned AxiBytes = soc_bus_pkg::AxiDataWidth / 8;
  localparam int unsigned LaneSelWidth = (AxiBytes > ObiBytes) ? $clog2(AxiBytes / ObiBytes) : 1;
  localparam int unsigned LaneCount = (AxiBytes > ObiBytes) ? (AxiBytes / ObiBytes) : 1;
  localparam int unsigned ObiByteW = (ObiBytes > 1) ? $clog2(ObiBytes) : 1;

  typedef enum logic [2:0] {
    StateIdle,
    StateWriteReq,
    StateWriteResp,
    StateReadReq,
    StateReadResp,
    StateErrResp
  } state_e;

  typedef struct packed {
    axi_pkg::size_t          size;
    logic [ObiAddrWidth-1:0] addr;
  } ax_enc_t;

  state_e state_q;
  logic [ObiAddrWidth-1:0]   addr_q;
  logic [ObiDataWidth-1:0]   wdata_q;
  logic [ObiDataWidth/8-1:0] be_q;
  logic                      aw_done_q;
  logic                      w_done_q;

  function automatic logic [LaneSelWidth-1:0] lane_sel(input logic [ObiAddrWidth-1:0] addr);
    if (LaneCount == 1) begin
      return '0;
    end
    return addr[$clog2(ObiBytes) +: LaneSelWidth];
  endfunction

  function automatic logic [soc_bus_pkg::AxiDataWidth-1:0] expand_wdata(
    input logic [ObiAddrWidth-1:0]   addr,
    input logic [ObiDataWidth-1:0]   wdata
  );
    logic [soc_bus_pkg::AxiDataWidth-1:0] result;
    result = '0;
    result[lane_sel(addr) * ObiDataWidth +: ObiDataWidth] = wdata;
    return result;
  endfunction

  function automatic logic [AxiBytes-1:0] expand_be(
    input logic [ObiAddrWidth-1:0]   addr,
    input logic [ObiDataWidth/8-1:0] be
  );
    logic [AxiBytes-1:0] result;
    result = '0;
    result[lane_sel(addr) * ObiBytes +: ObiBytes] = be;
    return result;
  endfunction

  function automatic logic [ObiDataWidth-1:0] select_rdata(
    input logic [ObiAddrWidth-1:0]                addr,
    input logic [soc_bus_pkg::AxiDataWidth-1:0]   rdata
  );
    return rdata[lane_sel(addr) * ObiDataWidth +: ObiDataWidth];
  endfunction

  // Encode the OBI byte enables as an AXI access size plus in-word byte
  // offset. RISC-V initiators (cores, debug SBA) issue naturally aligned
  // byte/half/word/double accesses, so `be` is a contiguous power-of-two run
  // aligned to its own size. AXI reads carry no strobes, so without this
  // narrow encoding every read would oblige the target to access the full bus
  // width - destructive on read-sensitive registers (e.g. the PLIC
  // claim/complete register behind soc_axi_to_reg). Patterns that do not
  // match (including all-zero read strobes from cores that leave `be` idle on
  // loads) fall back to a full-width access at the aligned address, which is
  // the previous behavior of this bridge.
  function automatic ax_enc_t ax_encode(
    input logic [ObiAddrWidth-1:0] addr,
    input logic [ObiBytes-1:0]     be
  );
    ax_enc_t     enc;
    int unsigned n;
    int unsigned off;
    n   = 0;
    off = 0;
    for (int unsigned i = 0; i < ObiBytes; i++) begin
      if (be[i]) begin
        n += 1;
      end
    end
    for (int unsigned i = ObiBytes; i > 0; i--) begin
      if (be[i-1]) begin
        off = i - 1;
      end
    end
    enc.size = axi_pkg::size_t'(unsigned'($clog2(ObiBytes)));
    enc.addr = {addr[ObiAddrWidth-1:ObiByteW], {ObiByteW{1'b0}}};
    if ((n inside {32'd1, 32'd2, 32'd4, 32'd8}) && ((off & (n - 1)) == 0) &&
        (be == ObiBytes'(((64'd1 << n) - 64'd1) << off))) begin
      unique case (n)
        32'd1:   enc.size = axi_pkg::size_t'(0);
        32'd2:   enc.size = axi_pkg::size_t'(1);
        32'd4:   enc.size = axi_pkg::size_t'(2);
        default: enc.size = axi_pkg::size_t'(3);
      endcase
      enc.addr = enc.addr | ObiAddrWidth'(off);
    end
    return enc;
  endfunction

  ax_enc_t ax_enc;
  assign ax_enc = ax_encode(addr_q, be_q);

  // Addresses above the fabric address space must error instead of silently
  // truncating into a mapped window (the 64-bit debug SBA can present any
  // 64-bit sbaddress).
  logic addr_oob;
  if (ObiAddrWidth > soc_bus_pkg::AxiAddrWidth) begin : gen_oob_check
    assign addr_oob = |s_addr_i[ObiAddrWidth-1:soc_bus_pkg::AxiAddrWidth];
  end else begin : gen_no_oob_check
    assign addr_oob = 1'b0;
  end

  always_comb begin
    m_axi_req_o = '0;
    s_gnt_o     = (state_q == StateIdle) && s_req_i;
    s_rvalid_o  = 1'b0;
    s_rdata_o   = '0;
    s_err_o     = 1'b0;

    unique case (state_q)
      StateWriteReq: begin
        m_axi_req_o.aw_valid    = !aw_done_q;
        m_axi_req_o.aw.id       = AxiId;
        m_axi_req_o.aw.addr     = soc_bus_pkg::AxiAddrWidth'(ax_enc.addr);
        m_axi_req_o.aw.len      = '0;
        m_axi_req_o.aw.size     = ax_enc.size;
        m_axi_req_o.aw.burst    = axi_pkg::BURST_INCR;
        m_axi_req_o.aw.lock     = 1'b0;
        m_axi_req_o.aw.cache    = '0;
        m_axi_req_o.aw.prot     = '0;
        m_axi_req_o.aw.qos      = '0;
        m_axi_req_o.aw.region   = '0;
        m_axi_req_o.aw.atop     = '0;
        m_axi_req_o.aw.user     = '0;

        m_axi_req_o.w_valid     = !w_done_q;
        m_axi_req_o.w.data      = expand_wdata(addr_q, wdata_q);
        m_axi_req_o.w.strb      = expand_be(addr_q, be_q);
        m_axi_req_o.w.last      = 1'b1;
        m_axi_req_o.w.user      = '0;
      end

      StateWriteResp: begin
        m_axi_req_o.b_ready = s_rready_i;
        s_rvalid_o          = m_axi_rsp_i.b_valid;
        s_err_o             = (m_axi_rsp_i.b.resp != axi_pkg::RESP_OKAY);
      end

      StateReadReq: begin
        m_axi_req_o.ar_valid    = 1'b1;
        m_axi_req_o.ar.id       = AxiId;
        m_axi_req_o.ar.addr     = soc_bus_pkg::AxiAddrWidth'(ax_enc.addr);
        m_axi_req_o.ar.len      = '0;
        m_axi_req_o.ar.size     = ax_enc.size;
        m_axi_req_o.ar.burst    = axi_pkg::BURST_INCR;
        m_axi_req_o.ar.lock     = 1'b0;
        m_axi_req_o.ar.cache    = '0;
        m_axi_req_o.ar.prot     = '0;
        m_axi_req_o.ar.qos      = '0;
        m_axi_req_o.ar.region   = '0;
        m_axi_req_o.ar.user     = '0;
      end

      StateReadResp: begin
        m_axi_req_o.r_ready = s_rready_i;
        s_rvalid_o          = m_axi_rsp_i.r_valid;
        s_rdata_o           = select_rdata(addr_q, m_axi_rsp_i.r.data);
        s_err_o             = (m_axi_rsp_i.r.resp != axi_pkg::RESP_OKAY) || !m_axi_rsp_i.r.last;
      end

      StateErrResp: begin
        s_rvalid_o = 1'b1;
        s_err_o    = 1'b1;
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= StateIdle;
      addr_q    <= '0;
      wdata_q   <= '0;
      be_q      <= '0;
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
    end else begin
      unique case (state_q)
        StateIdle: begin
          aw_done_q <= 1'b0;
          w_done_q  <= 1'b0;
          if (s_req_i) begin
            addr_q  <= s_addr_i;
            wdata_q <= s_wdata_i;
            be_q    <= s_be_i;
            if (addr_oob) begin
              state_q <= StateErrResp;
            end else begin
              state_q <= s_we_i ? StateWriteReq : StateReadReq;
            end
          end
        end

        StateWriteReq: begin
          if (m_axi_req_o.aw_valid && m_axi_rsp_i.aw_ready) begin
            aw_done_q <= 1'b1;
          end
          if (m_axi_req_o.w_valid && m_axi_rsp_i.w_ready) begin
            w_done_q <= 1'b1;
          end
          if ((aw_done_q || (m_axi_req_o.aw_valid && m_axi_rsp_i.aw_ready)) &&
              (w_done_q  || (m_axi_req_o.w_valid  && m_axi_rsp_i.w_ready))) begin
            state_q <= StateWriteResp;
          end
        end

        StateWriteResp: begin
          if (m_axi_rsp_i.b_valid && s_rready_i) begin
            state_q <= StateIdle;
          end
        end

        StateReadReq: begin
          if (m_axi_req_o.ar_valid && m_axi_rsp_i.ar_ready) begin
            state_q <= StateReadResp;
          end
        end

        StateReadResp: begin
          if (m_axi_rsp_i.r_valid && s_rready_i) begin
            state_q <= StateIdle;
          end
        end

        StateErrResp: begin
          if (s_rready_i) begin
            state_q <= StateIdle;
          end
        end

        default: begin
          state_q <= StateIdle;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (m_axi_req_o.aw_valid && !m_axi_rsp_i.aw_ready) begin
        assert (m_axi_req_o.aw.addr == soc_bus_pkg::AxiAddrWidth'(ax_enc.addr));
      end
      if (m_axi_req_o.w_valid && !m_axi_rsp_i.w_ready) begin
        assert (m_axi_req_o.w.strb == expand_be(addr_q, be_q));
      end
      if (m_axi_req_o.ar_valid && !m_axi_rsp_i.ar_ready) begin
        assert (m_axi_req_o.ar.addr == soc_bus_pkg::AxiAddrWidth'(ax_enc.addr));
      end
    end
  end
`endif
endmodule
