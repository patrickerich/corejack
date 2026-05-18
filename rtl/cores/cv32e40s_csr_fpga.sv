// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// FPGA-oriented replacement for the CV32E40S CSR primitive.
//
// The upstream hardened CSR implementation uses local clock gates as write
// enables for the data/shadow registers. That is suitable for ASIC libraries
// with proper integrated clock-gating cells, but it maps to LUT-driven clocks
// on this FPGA flow. Keep the same module interface and shadow-copy behavior,
// but express the update condition as a flip-flop clock enable.
module cv32e40s_csr #(
  parameter                 LIB = 0,
  parameter int unsigned    WIDTH = 32,
  parameter bit             SHADOWCOPY = 1'b0,
  parameter bit [WIDTH-1:0] RESETVALUE = '0,
  parameter bit [WIDTH-1:0] MASK = {WIDTH{1'b1}}
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic             scan_cg_en_i,

  input  logic [WIDTH-1:0] wr_data_i,
  input  logic             wr_en_i,
  output logic [WIDTH-1:0] rd_data_o,

  output logic             rd_error_o
);
  logic [WIDTH-1:0] rdata_q;
  logic             unused_lib;

  assign unused_lib = ^LIB;
  assign rd_data_o  = rdata_q;

  generate
    if (SHADOWCOPY) begin : gen_hardened
      logic [WIDTH-1:0] shadow_q;
      logic             wr_en;

      assign wr_en      = wr_en_i | scan_cg_en_i;
      assign rd_error_o = rdata_q != ~shadow_q;

      for (genvar i = 0; i < WIDTH; i++) begin : gen_csr_hardened
        if (MASK[i]) begin : gen_unmasked_hardened
          always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
              rdata_q[i]  <= RESETVALUE[i];
              shadow_q[i] <= ~RESETVALUE[i];
            end else if (wr_en) begin
              rdata_q[i]  <= wr_data_i[i];
              shadow_q[i] <= ~wr_data_i[i];
            end
          end
        end else begin : gen_masked_hardened
          assign rdata_q[i]  = RESETVALUE[i];
          assign shadow_q[i] = ~RESETVALUE[i];
        end
      end
    end else begin : gen_unhardened
      for (genvar i = 0; i < WIDTH; i++) begin : gen_csr_unhardened
        if (MASK[i]) begin : gen_unmasked_unhardened
          always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
              rdata_q[i] <= RESETVALUE[i];
            end else if (wr_en_i) begin
              rdata_q[i] <= wr_data_i[i];
            end
          end
        end else begin : gen_masked_unhardened
          assign rdata_q[i] = RESETVALUE[i];
        end
      end

      assign rd_error_o = 1'b0;
    end
  endgenerate
endmodule
