module soc_axi_demux #(
  parameter int unsigned NumMstPorts = 2,
  parameter int unsigned NoAddrRules = 1,
  parameter type rule_t = axi_pkg::xbar_rule_32_t
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  soc_bus_pkg::soc_axi_req_t                      slv_req_i,
  output soc_bus_pkg::soc_axi_resp_t                     slv_resp_o,
  output soc_bus_pkg::soc_axi_req_t  [NumMstPorts-1:0]   mst_reqs_o,
  input  soc_bus_pkg::soc_axi_resp_t [NumMstPorts-1:0]   mst_resps_i,
  input  rule_t                      [NoAddrRules-1:0]   addr_map_i
);
  import axi_pkg::*;

  localparam int unsigned MstSelWidth = (NumMstPorts > 1) ? $clog2(NumMstPorts) : 1;
  typedef logic [MstSelWidth-1:0] mst_sel_t;

  typedef enum logic [1:0] {
    StateIdle,
    StateWriteResp,
    StateReadResp
  } state_e;

  state_e   state_q;
  mst_sel_t active_q;
  logic     active_error_q;
  soc_bus_pkg::axi_id_t active_id_q;

  logic     aw_dec_valid;
  logic     aw_dec_error;
  mst_sel_t aw_dec_idx;
  logic     ar_dec_valid;
  logic     ar_dec_error;
  mst_sel_t ar_dec_idx;
  logic     write_valid;
  logic     read_valid;
  logic     select_write;
  mst_sel_t select_idx;
  logic     select_error;

  addr_decode #(
    .NoIndices (NumMstPorts),
    .NoRules   (NoAddrRules),
    .addr_t    (logic [31:0]),
    .rule_t    (rule_t),
    .idx_t     (mst_sel_t)
  ) i_aw_decode (
    .addr_i           (slv_req_i.aw.addr[31:0]),
    .addr_map_i       (addr_map_i),
    .idx_o            (aw_dec_idx),
    .dec_valid_o      (aw_dec_valid),
    .dec_error_o      (aw_dec_error),
    .en_default_idx_i (1'b0),
    .default_idx_i    ('0)
  );

  addr_decode #(
    .NoIndices (NumMstPorts),
    .NoRules   (NoAddrRules),
    .addr_t    (logic [31:0]),
    .rule_t    (rule_t),
    .idx_t     (mst_sel_t)
  ) i_ar_decode (
    .addr_i           (slv_req_i.ar.addr[31:0]),
    .addr_map_i       (addr_map_i),
    .idx_o            (ar_dec_idx),
    .dec_valid_o      (ar_dec_valid),
    .dec_error_o      (ar_dec_error),
    .en_default_idx_i (1'b0),
    .default_idx_i    ('0)
  );

  assign write_valid  = slv_req_i.aw_valid && slv_req_i.w_valid;
  assign read_valid   = slv_req_i.ar_valid && !write_valid;
  assign select_write = write_valid;
  assign select_idx   = write_valid ? aw_dec_idx : ar_dec_idx;
  assign select_error = write_valid ? (!aw_dec_valid || aw_dec_error) :
                                      (!ar_dec_valid || ar_dec_error);

  always_comb begin
    slv_resp_o = '0;
    mst_reqs_o = '0;

    unique case (state_q)
      StateIdle: begin
        if (write_valid) begin
          if (select_error) begin
            slv_resp_o.aw_ready = 1'b1;
            slv_resp_o.w_ready  = 1'b1;
          end else begin
            mst_reqs_o[select_idx].aw_valid = slv_req_i.aw_valid;
            mst_reqs_o[select_idx].aw       = slv_req_i.aw;
            mst_reqs_o[select_idx].w_valid  = slv_req_i.w_valid;
            mst_reqs_o[select_idx].w        = slv_req_i.w;
            slv_resp_o.aw_ready = mst_resps_i[select_idx].aw_ready &&
                                  mst_resps_i[select_idx].w_ready;
            slv_resp_o.w_ready  = slv_resp_o.aw_ready;
          end
        end else if (read_valid) begin
          if (select_error) begin
            slv_resp_o.ar_ready = 1'b1;
          end else begin
            mst_reqs_o[select_idx].ar_valid = slv_req_i.ar_valid;
            mst_reqs_o[select_idx].ar       = slv_req_i.ar;
            slv_resp_o.ar_ready = mst_resps_i[select_idx].ar_ready;
          end
        end
      end

      StateWriteResp: begin
        if (active_error_q) begin
          slv_resp_o.b_valid = 1'b1;
          slv_resp_o.b.id    = active_id_q;
          slv_resp_o.b.resp  = axi_pkg::RESP_DECERR;
          slv_resp_o.b.user  = '0;
        end else begin
          mst_reqs_o[active_q].b_ready = slv_req_i.b_ready;
          slv_resp_o.b_valid = mst_resps_i[active_q].b_valid;
          slv_resp_o.b       = mst_resps_i[active_q].b;
        end
      end

      StateReadResp: begin
        if (active_error_q) begin
          slv_resp_o.r_valid = 1'b1;
          slv_resp_o.r.id    = active_id_q;
          slv_resp_o.r.data  = '0;
          slv_resp_o.r.resp  = axi_pkg::RESP_DECERR;
          slv_resp_o.r.last  = 1'b1;
          slv_resp_o.r.user  = '0;
        end else begin
          mst_reqs_o[active_q].r_ready = slv_req_i.r_ready;
          slv_resp_o.r_valid = mst_resps_i[active_q].r_valid;
          slv_resp_o.r       = mst_resps_i[active_q].r;
        end
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q        <= StateIdle;
      active_q       <= '0;
      active_error_q <= 1'b0;
      active_id_q    <= '0;
    end else begin
      unique case (state_q)
        StateIdle: begin
          if (write_valid &&
              (select_error || (mst_resps_i[select_idx].aw_ready && mst_resps_i[select_idx].w_ready))) begin
            active_q       <= select_idx;
            active_error_q <= select_error;
            active_id_q    <= slv_req_i.aw.id;
            state_q        <= StateWriteResp;
          end else if (read_valid &&
                       (select_error || mst_resps_i[select_idx].ar_ready)) begin
            active_q       <= select_idx;
            active_error_q <= select_error;
            active_id_q    <= slv_req_i.ar.id;
            state_q        <= StateReadResp;
          end
        end

        StateWriteResp: begin
          if ((active_error_q && slv_req_i.b_ready) ||
              (!active_error_q && mst_resps_i[active_q].b_valid && slv_req_i.b_ready)) begin
            state_q <= StateIdle;
          end
        end

        StateReadResp: begin
          if ((active_error_q && slv_req_i.r_ready) ||
              (!active_error_q && mst_resps_i[active_q].r_valid && slv_req_i.r_ready)) begin
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
