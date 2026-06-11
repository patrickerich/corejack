// SPDX-License-Identifier: Apache-2.0
//
// CoreJack wrapper around the PULP iDMA engine.
//
// Composition (the same shape Cheshire uses):
//   idma_reg32_3d (register frontend, one reg port, one stream)
//     -> idma_nd_midend (flattens the up-to-3D request into 1D bursts)
//     -> idma_backend_rw_axi (AXI4 read + write managers)
//     -> axi_rw_join (merges the two managers into one AXI port)
//     -> axi_burst_splitter (splits bursts into single-beat transfers)
//
// The burst splitter keeps the CoreJack platform invariant that every fabric
// transaction is single-beat (len == 0), which is what the target adapters
// and soc_axi_protocol_checker assume. Removing it is the natural first step
// of the roadmap's "add burst support" item.
//
// Software contract (see sw/c/common/dma.h): program SRC_ADDR_LOW /
// DST_ADDR_LOW / LENGTH_LOW and CONF (0 selects a plain 1D AXI-to-AXI
// transfer), then read NEXT_ID_0 to launch; the read returns the transfer id.
// Poll DONE_ID_0 until it reaches that id.

`include "idma/typedef.svh"

module soc_idma #(
  parameter int unsigned NumAxInFlight = 2,
  parameter type reg_req_t = soc_bus_pkg::soc_reg_req_t,
  parameter type reg_rsp_t = soc_bus_pkg::soc_reg_rsp_t,
  parameter type axi_req_t = soc_bus_pkg::soc_axi_req_t,
  parameter type axi_rsp_t = soc_bus_pkg::soc_axi_resp_t
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  reg_req_t reg_req_i,
  output reg_rsp_t reg_rsp_o,

  output axi_req_t m_axi_req_o,
  input  axi_rsp_t m_axi_rsp_i,

  output logic busy_o
);
  import soc_bus_pkg::*;

  localparam int unsigned TfLenWidth = 32;
  localparam int unsigned IdCounterWidth = 32;
  // The reg32_3d frontend supports up to three dimensions; CoreJack uses
  // plain 1D transfers (CONF.enable_nd = 0) but the midend must match the
  // frontend's request shape.
  localparam int unsigned NumDim = 3;

  typedef logic [TfLenWidth-1:0] tf_len_t;
  typedef logic [IdCounterWidth-1:0] tf_id_t;
  typedef logic [31:0] reps_t;
  typedef logic [31:0] strides_t;

  // iDMA request/response types (1D and ND variants).
  `IDMA_TYPEDEF_FULL_REQ_T(idma_req_t, axi_id_t, axi_addr_t, tf_len_t)
  `IDMA_TYPEDEF_FULL_RSP_T(idma_rsp_t, axi_addr_t)
  `IDMA_TYPEDEF_FULL_ND_REQ_T(idma_nd_req_t, idma_req_t, reps_t, strides_t)

  // Meta-channel wrappers the generated backend expects.
  typedef struct packed {
    soc_axi_ar_chan_t ar_chan;
  } axi_read_meta_channel_t;

  typedef struct packed {
    axi_read_meta_channel_t axi;
  } read_meta_channel_t;

  typedef struct packed {
    soc_axi_aw_chan_t aw_chan;
  } axi_write_meta_channel_t;

  typedef struct packed {
    axi_write_meta_channel_t axi;
  } write_meta_channel_t;

  // Frontend -> midend ND request stream.
  idma_nd_req_t nd_req;
  logic         nd_req_valid;
  logic         nd_req_ready;
  idma_rsp_t    nd_rsp;
  logic         nd_rsp_valid;

  // Midend -> backend 1D burst stream.
  idma_req_t burst_req;
  logic      burst_req_valid;
  logic      burst_req_ready;
  idma_rsp_t burst_rsp;
  logic      burst_rsp_valid;
  logic      burst_rsp_ready;

  // Transfer id bookkeeping and busy aggregation.
  tf_id_t next_id;
  tf_id_t done_id;
  logic   midend_busy;
  idma_pkg::idma_busy_t backend_busy;

  // Backend AXI managers before the join, the joined burst-capable port, and
  // the single-beat port before the output cut.
  axi_req_t axi_read_req;
  axi_rsp_t axi_read_rsp;
  axi_req_t axi_write_req;
  axi_rsp_t axi_write_rsp;
  axi_req_t axi_burst_req;
  axi_rsp_t axi_burst_rsp;
  axi_req_t axi_burst_cut_req;
  axi_rsp_t axi_burst_cut_rsp;
  axi_req_t axi_split_req;
  axi_rsp_t axi_split_rsp;

  idma_reg32_3d #(
    .NumRegs        (32'd1),
    .NumStreams     (32'd1),
    .IdCounterWidth (IdCounterWidth),
    .reg_req_t      (reg_req_t),
    .reg_rsp_t      (reg_rsp_t),
    .dma_req_t      (idma_nd_req_t)
  ) i_idma_frontend (
    .clk_i,
    .rst_ni,
    .dma_ctrl_req_i (reg_req_i),
    .dma_ctrl_rsp_o (reg_rsp_o),
    .dma_req_o      (nd_req),
    .req_valid_o    (nd_req_valid),
    .req_ready_i    (nd_req_ready),
    .next_id_i      (next_id),
    .stream_idx_o   (/* single stream */),
    .done_id_i      (done_id),
    .busy_i         (backend_busy),
    .midend_busy_i  (midend_busy)
  );

  idma_transfer_id_gen #(
    .IdWidth (IdCounterWidth)
  ) i_idma_transfer_id_gen (
    .clk_i,
    .rst_ni,
    .issue_i     (nd_req_valid && nd_req_ready),
    .retire_i    (nd_rsp_valid),
    .next_o      (next_id),
    .completed_o (done_id)
  );

  idma_nd_midend #(
    .NumDim        (NumDim),
    .addr_t        (axi_addr_t),
    .idma_req_t    (idma_req_t),
    .idma_rsp_t    (idma_rsp_t),
    .idma_nd_req_t (idma_nd_req_t),
    .RepWidths     ('{default: 32'd32})
  ) i_idma_nd_midend (
    .clk_i,
    .rst_ni,
    .nd_req_i          (nd_req),
    .nd_req_valid_i    (nd_req_valid),
    .nd_req_ready_o    (nd_req_ready),
    .nd_rsp_o          (nd_rsp),
    .nd_rsp_valid_o    (nd_rsp_valid),
    .nd_rsp_ready_i    (1'b1),
    .burst_req_o       (burst_req),
    .burst_req_valid_o (burst_req_valid),
    .burst_req_ready_i (burst_req_ready),
    .burst_rsp_i       (burst_rsp),
    .burst_rsp_valid_i (burst_rsp_valid),
    .burst_rsp_ready_o (burst_rsp_ready),
    .busy_o            (midend_busy)
  );

  idma_backend_rw_axi #(
    .DataWidth            (AxiDataWidth),
    .AddrWidth            (AxiAddrWidth),
    .UserWidth            (32'd1),
    .AxiIdWidth           (AxiIdWidth),
    .NumAxInFlight        (NumAxInFlight),
    .BufferDepth          (32'd3),
    .TFLenWidth           (TfLenWidth),
    .ErrorCap             (idma_pkg::NO_ERROR_HANDLING),
    .idma_req_t           (idma_req_t),
    .idma_rsp_t           (idma_rsp_t),
    .idma_eh_req_t        (idma_pkg::idma_eh_req_t),
    .idma_busy_t          (idma_pkg::idma_busy_t),
    .axi_req_t            (axi_req_t),
    .axi_rsp_t            (axi_rsp_t),
    .read_meta_channel_t  (read_meta_channel_t),
    .write_meta_channel_t (write_meta_channel_t)
  ) i_idma_backend (
    .clk_i,
    .rst_ni,
    .testmode_i      (1'b0),
    .idma_req_i      (burst_req),
    .req_valid_i     (burst_req_valid),
    .req_ready_o     (burst_req_ready),
    .idma_rsp_o      (burst_rsp),
    .rsp_valid_o     (burst_rsp_valid),
    .rsp_ready_i     (burst_rsp_ready),
    .idma_eh_req_i   ('0),
    .eh_req_valid_i  (1'b0),
    .eh_req_ready_o  (/* unused, no error handling */),
    .axi_read_req_o  (axi_read_req),
    .axi_read_rsp_i  (axi_read_rsp),
    .axi_write_req_o (axi_write_req),
    .axi_write_rsp_i (axi_write_rsp),
    .busy_o          (backend_busy)
  );

  axi_rw_join #(
    .axi_req_t  (axi_req_t),
    .axi_resp_t (axi_rsp_t)
  ) i_axi_rw_join (
    .clk_i,
    .rst_ni,
    .slv_read_req_i   (axi_read_req),
    .slv_read_resp_o  (axi_read_rsp),
    .slv_write_req_i  (axi_write_req),
    .slv_write_resp_o (axi_write_rsp),
    .mst_req_o        (axi_burst_req),
    .mst_resp_i       (axi_burst_rsp)
  );

  // Register the backend/splitter boundary: the backend's coupled AW/W/R
  // spill logic and the splitter's in-flight counters otherwise close a
  // combinational loop of their own (Vivado DRC LUTLP-1).
  axi_cut #(
    .Bypass     (1'b0),
    .aw_chan_t  (soc_axi_aw_chan_t),
    .w_chan_t   (soc_axi_w_chan_t),
    .b_chan_t   (soc_axi_b_chan_t),
    .ar_chan_t  (soc_axi_ar_chan_t),
    .r_chan_t   (soc_axi_r_chan_t),
    .axi_req_t  (axi_req_t),
    .axi_resp_t (axi_rsp_t)
  ) i_axi_cut_backend (
    .clk_i,
    .rst_ni,
    .slv_req_i  (axi_burst_req),
    .slv_resp_o (axi_burst_rsp),
    .mst_req_o  (axi_burst_cut_req),
    .mst_resp_i (axi_burst_cut_rsp)
  );

  axi_burst_splitter #(
    .MaxReadTxns  (32'd4),
    .MaxWriteTxns (32'd4),
    .FullBW       (1'b0),
    .AddrWidth    (AxiAddrWidth),
    .DataWidth    (AxiDataWidth),
    .IdWidth      (AxiIdWidth),
    .UserWidth    (32'd1),
    .axi_req_t    (axi_req_t),
    .axi_resp_t   (axi_rsp_t)
  ) i_axi_burst_splitter (
    .clk_i,
    .rst_ni,
    .slv_req_i  (axi_burst_cut_req),
    .slv_resp_o (axi_burst_cut_rsp),
    .mst_req_o  (axi_split_req),
    .mst_resp_i (axi_split_rsp)
  );

  // Register all five AXI channels at the DMA's fabric boundary. The iDMA
  // backend couples its W stream to its R stream (memcpy), and through a
  // crossbar with combinational W routing that coupling closes a structural
  // combinational loop with the valid-dependent readies of the target
  // adapters (Vivado DRC LUTLP-1). The cut keeps the DMA leg fully
  // registered while CPU paths stay latency-free.
  axi_cut #(
    .Bypass     (1'b0),
    .aw_chan_t  (soc_axi_aw_chan_t),
    .w_chan_t   (soc_axi_w_chan_t),
    .b_chan_t   (soc_axi_b_chan_t),
    .ar_chan_t  (soc_axi_ar_chan_t),
    .r_chan_t   (soc_axi_r_chan_t),
    .axi_req_t  (axi_req_t),
    .axi_resp_t (axi_rsp_t)
  ) i_axi_cut (
    .clk_i,
    .rst_ni,
    .slv_req_i  (axi_split_req),
    .slv_resp_o (axi_split_rsp),
    .mst_req_o  (m_axi_req_o),
    .mst_resp_i (m_axi_rsp_i)
  );

  assign busy_o = midend_busy || (|backend_busy);
endmodule
