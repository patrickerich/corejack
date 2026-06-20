// SPDX-License-Identifier: Apache-2.0
//
// OBI (single-beat) to soc_mem_ss init-port bridge.
//
// Drives a narrow OBI master (e.g. an RV32 core's data port) directly onto a
// soc_mem_ss init port, bypassing the AXI crossbar so the access runs on its
// own memory port concurrently with the other initiators' ports. The init-port
// protocol is itself a single-channel read-or-write request/response bus, so
// this is a thin lane-adapting pass-through rather than a full protocol bridge:
// it expands the narrow OBI word into the selected lane of the wider memory
// word (using the byte address) and selects that lane back out of the read
// response.
//
// Single-outstanding: one transaction is accepted and run to its response
// before the next is granted, so the soc_mem_ss single-outstanding-per-port
// contract holds and OBI responses stay in order.
module soc_obi_to_mem #(
  parameter int unsigned ObiAddrWidth = 32,
  parameter int unsigned ObiDataWidth = 32,
  parameter int unsigned MemAddrWidth = 32,
  parameter int unsigned MemDataWidth = 64
) (
  input  logic clk_i,
  input  logic rst_ni,

  // OBI slave (narrow, from the core data path).
  input  logic                      s_req_i,
  output logic                      s_gnt_o,
  input  logic                      s_we_i,
  input  logic [ObiAddrWidth-1:0]   s_addr_i,
  input  logic [ObiDataWidth-1:0]   s_wdata_i,
  input  logic [ObiDataWidth/8-1:0] s_be_i,
  output logic                      s_rvalid_o,
  input  logic                      s_rready_i,
  output logic [ObiDataWidth-1:0]   s_rdata_o,
  output logic                      s_err_o,

  // soc_mem_ss init-port master (wide).
  output logic                      mem_req_o,
  output logic                      mem_we_o,
  output logic [MemAddrWidth-1:0]   mem_addr_o,
  output logic [MemDataWidth-1:0]   mem_wdata_o,
  output logic [MemDataWidth/8-1:0] mem_be_o,
  input  logic                      mem_gnt_i,
  input  logic                      mem_rvalid_i,
  output logic                      mem_rready_o,
  input  logic [MemDataWidth-1:0]   mem_rdata_i,
  input  logic                      mem_err_i
);
  localparam int unsigned ObiBytes = ObiDataWidth / 8;
  localparam int unsigned MemBytes = MemDataWidth / 8;
  localparam int unsigned LaneSelWidth = (MemBytes > ObiBytes) ? $clog2(MemBytes / ObiBytes) : 1;
  localparam int unsigned LaneCount = (MemBytes > ObiBytes) ? (MemBytes / ObiBytes) : 1;

  function automatic logic [LaneSelWidth-1:0] lane_sel(input logic [ObiAddrWidth-1:0] addr);
    if (LaneCount == 1) begin
      return '0;
    end
    return addr[$clog2(ObiBytes) +: LaneSelWidth];
  endfunction

  function automatic logic [MemDataWidth-1:0] expand_wdata(
    input logic [ObiAddrWidth-1:0] addr,
    input logic [ObiDataWidth-1:0] wdata
  );
    logic [MemDataWidth-1:0] result;
    result = '0;
    result[lane_sel(addr) * ObiDataWidth +: ObiDataWidth] = wdata;
    return result;
  endfunction

  function automatic logic [MemBytes-1:0] expand_be(
    input logic [ObiAddrWidth-1:0]   addr,
    input logic [ObiDataWidth/8-1:0] be
  );
    logic [MemBytes-1:0] result;
    result = '0;
    result[lane_sel(addr) * ObiBytes +: ObiBytes] = be;
    return result;
  endfunction

  function automatic logic [ObiDataWidth-1:0] select_rdata(
    input logic [LaneSelWidth-1:0]   lane,
    input logic [MemDataWidth-1:0]   rdata
  );
    return rdata[lane * ObiDataWidth +: ObiDataWidth];
  endfunction

  typedef enum logic {StateIdle, StateWait} state_e;
  state_e state_q;
  logic [LaneSelWidth-1:0] lane_q;

  always_comb begin
    mem_req_o    = 1'b0;
    mem_we_o     = 1'b0;
    mem_addr_o   = '0;
    mem_wdata_o  = '0;
    mem_be_o     = '0;
    mem_rready_o = 1'b1;
    s_gnt_o      = 1'b0;
    s_rvalid_o   = 1'b0;
    s_rdata_o    = '0;
    s_err_o      = 1'b0;

    unique case (state_q)
      StateIdle: begin
        mem_req_o   = s_req_i;
        mem_we_o    = s_we_i;
        mem_addr_o  = MemAddrWidth'(s_addr_i);
        mem_wdata_o = expand_wdata(s_addr_i, s_wdata_i);
        mem_be_o    = expand_be(s_addr_i, s_be_i);
        s_gnt_o     = s_req_i & mem_gnt_i;
      end

      StateWait: begin
        mem_rready_o = s_rready_i;
        s_rvalid_o   = mem_rvalid_i;
        s_rdata_o    = select_rdata(lane_q, mem_rdata_i);
        s_err_o      = mem_err_i;
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      lane_q  <= '0;
    end else begin
      unique case (state_q)
        StateIdle: begin
          if (s_req_i && mem_gnt_i) begin
            lane_q  <= lane_sel(s_addr_i);
            state_q <= StateWait;
          end
        end

        StateWait: begin
          if (mem_rvalid_i && s_rready_i) begin
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
