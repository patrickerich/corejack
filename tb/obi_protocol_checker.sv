// SPDX-License-Identifier: Apache-2.0
//
// Simulation checker for one request/response bus between a core and the bus
// side of the platform, in the OBI style of the core socket: a request is
// accepted in a cycle where req and gnt are both high, and every accepted
// request is answered by one rvalid in a later cycle.
//
// The core has its own reset, core_rst_ni. The bus side stays out of that
// reset and completes what the core started, so the checker runs on the
// bus-side reset rst_ni. It checks four rules:
//
// 1. A request that is not granted stays up, with the same address, write
//    enable and byte enables, and for a write the same write data.
// 2. Nothing is accepted from a core that is in reset.
// 3. A response only arrives while an access is outstanding.
// 4. No access is outstanding when the core reset releases. Responses carry
//    no tag, so one that arrived after the release would answer the first
//    request of the restarted core.
//
// inject_i reports an access that the testbench had accepted below this bus,
// on the far side of the socket's buffer. Its response returns over this bus,
// so it counts as outstanding.
module obi_protocol_checker #(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 32
) (
  input logic                   clk_i,
  input logic                   rst_ni,
  input logic                   core_rst_ni,
  input logic                   req_i,
  input logic                   gnt_i,
  input logic                   we_i,
  input logic [AddrWidth-1:0]   addr_i,
  input logic [DataWidth-1:0]   wdata_i,
  input logic [DataWidth/8-1:0] be_i,
  input logic                   rvalid_i,
  input logic                   inject_i
);
  localparam int unsigned CountWidth = 8;

  typedef struct packed {
    logic                   we;
    logic [AddrWidth-1:0]   addr;
    logic [DataWidth-1:0]   wdata;
    logic [DataWidth/8-1:0] be;
  } req_payload_t;

  req_payload_t          payload;
  req_payload_t          payload_q;
  logic                  stalled_q;
  logic                  core_rst_nq;
  logic                  accepted;
  logic [CountWidth-1:0] outstanding_d;
  logic [CountWidth-1:0] outstanding_q;

  // Write data is only meaningful for a write.
  assign payload = '{
    we:    we_i,
    addr:  addr_i,
    wdata: we_i ? wdata_i : '0,
    be:    be_i
  };

  assign accepted      = req_i && gnt_i;
  assign outstanding_d = outstanding_q + CountWidth'(accepted) + CountWidth'(inject_i) -
                         CountWidth'(rvalid_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      payload_q     <= '0;
      stalled_q     <= 1'b0;
      core_rst_nq   <= 1'b0;
      outstanding_q <= '0;
    end else begin
      // Rule 1. A core reset may withdraw the request, so it ends the check.
      if (stalled_q && core_rst_ni) begin
        assert (req_i)
          else $error("request withdrawn before it was granted");
        assert (!req_i || (payload == payload_q))
          else $error("request changed before it was granted");
      end

      // Rule 2.
      assert (core_rst_ni || !accepted)
        else $error("request accepted from a core in reset");

      // Rule 3.
      assert (!rvalid_i || (outstanding_q != '0))
        else $error("response with no access outstanding");

      // Rule 4.
      if (core_rst_ni && !core_rst_nq) begin
        assert (outstanding_q == '0)
          else $error("core reset released with %0d access(es) outstanding", outstanding_q);
      end

      assert (outstanding_q != '1)
        else $error("outstanding access counter is about to wrap");

      payload_q     <= payload;
      stalled_q     <= req_i && !gnt_i && core_rst_ni;
      core_rst_nq   <= core_rst_ni;
      outstanding_q <= outstanding_d;
    end
  end
endmodule
