// SPDX-License-Identifier: Apache-2.0
//
// Accelerator socket: the uniform boundary between the CoreJack platform and
// a pluggable accelerator/system-IP block. The platform provides clock,
// reset, power-intent controls, and the CSR request stream; the accelerator
// drives its AXI memory manager, the CSR response, and one interrupt line
// (which the platform routes to a PLIC source).
//
// The CSR port speaks APB (the peripheral-subsystem protocol); blocks with a
// different native CSR protocol convert inside their adapter, see
// corejack_idma_socket_adapter. The memory port carries the platform
// initiator-side AXI types and must obey the single-beat fabric invariant
// (len == 0), e.g. by instantiating an axi_burst_splitter.
//
// The platform currently drives the power-intent pins to the static active
// state (power_en = 1, isolate = 0, retain = 0, clk_en = 1); adapters assert
// this until a platform power controller exists.

interface accel_socket_if #(
  parameter type mem_axi_req_t = logic,
  parameter type mem_axi_rsp_t = logic,
  parameter type csr_apb_req_t = logic,
  parameter type csr_apb_rsp_t = logic
);
  logic clk;
  logic rst_n;
  logic irq_o;

  logic power_en;
  logic isolate;
  logic retain;
  logic clk_en;

  mem_axi_req_t mem_req;
  mem_axi_rsp_t mem_rsp;

  csr_apb_req_t csr_req;
  csr_apb_rsp_t csr_rsp;

  modport accel (
    input  clk,
    input  rst_n,
    input  power_en,
    input  isolate,
    input  retain,
    input  clk_en,
    input  mem_rsp,
    input  csr_req,
    output irq_o,
    output mem_req,
    output csr_rsp
  );

  modport platform (
    output clk,
    output rst_n,
    output power_en,
    output isolate,
    output retain,
    output clk_en,
    output mem_rsp,
    output csr_req,
    input  irq_o,
    input  mem_req,
    input  csr_rsp
  );
endinterface
