module soc_axi_arbiter #(
  parameter int unsigned NumSlvPorts = 2
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  soc_bus_pkg::soc_axi_req_t  [NumSlvPorts-1:0] slv_reqs_i,
  output soc_bus_pkg::soc_axi_resp_t [NumSlvPorts-1:0] slv_resps_o,
  output soc_bus_pkg::soc_axi_req_t                      mst_req_o,
  input  soc_bus_pkg::soc_axi_resp_t                     mst_resp_i
);
  import axi_pkg::*;

  localparam int unsigned SlvSelWidth = (NumSlvPorts > 1) ? $clog2(NumSlvPorts) : 1;
  typedef logic [SlvSelWidth-1:0] slv_sel_t;

  typedef enum logic [1:0] {
    StateIdle,
    StateWriteResp,
    StateReadResp
  } state_e;

  state_e   state_q;
  slv_sel_t active_q;
  slv_sel_t rr_q;

  logic [NumSlvPorts-1:0] req_valid;
  logic [NumSlvPorts-1:0] write_valid;
  logic [NumSlvPorts-1:0] read_valid;
  logic                   select_valid;
  slv_sel_t               select_idx;
  logic                   select_write;

  for (genvar i = 0; i < NumSlvPorts; i++) begin : gen_req_valid
    assign write_valid[i] = slv_reqs_i[i].aw_valid && slv_reqs_i[i].w_valid;
    assign read_valid[i]  = slv_reqs_i[i].ar_valid;
    assign req_valid[i]   = write_valid[i] || read_valid[i];
  end

  always_comb begin
    int unsigned idx;

    select_valid = 1'b0;
    select_idx   = '0;
    select_write = 1'b0;

    for (int unsigned offset = 0; offset < NumSlvPorts; offset++) begin
      idx = (int'(rr_q) + offset) % NumSlvPorts;
      if (!select_valid && req_valid[idx]) begin
        select_valid = 1'b1;
        select_idx   = slv_sel_t'(idx);
        select_write = write_valid[idx];
      end
    end
  end

  always_comb begin
    mst_req_o   = '0;
    slv_resps_o = '0;

    unique case (state_q)
      StateIdle: begin
        if (select_valid) begin
          if (select_write) begin
            mst_req_o.aw_valid = slv_reqs_i[select_idx].aw_valid;
            mst_req_o.aw       = slv_reqs_i[select_idx].aw;
            mst_req_o.w_valid  = slv_reqs_i[select_idx].w_valid;
            mst_req_o.w        = slv_reqs_i[select_idx].w;

            slv_resps_o[select_idx].aw_ready = mst_resp_i.aw_ready && mst_resp_i.w_ready;
            slv_resps_o[select_idx].w_ready  = mst_resp_i.aw_ready && mst_resp_i.w_ready;
          end else begin
            mst_req_o.ar_valid = slv_reqs_i[select_idx].ar_valid;
            mst_req_o.ar       = slv_reqs_i[select_idx].ar;

            slv_resps_o[select_idx].ar_ready = mst_resp_i.ar_ready;
          end
        end
      end

      StateWriteResp: begin
        mst_req_o.b_ready = slv_reqs_i[active_q].b_ready;
        slv_resps_o[active_q].b_valid = mst_resp_i.b_valid;
        slv_resps_o[active_q].b       = mst_resp_i.b;
      end

      StateReadResp: begin
        mst_req_o.r_ready = slv_reqs_i[active_q].r_ready;
        slv_resps_o[active_q].r_valid = mst_resp_i.r_valid;
        slv_resps_o[active_q].r       = mst_resp_i.r;
      end

      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= StateIdle;
      active_q <= '0;
      rr_q     <= '0;
    end else begin
      unique case (state_q)
        StateIdle: begin
          if (select_valid && select_write && mst_resp_i.aw_ready && mst_resp_i.w_ready) begin
            active_q <= select_idx;
            state_q  <= StateWriteResp;
            rr_q     <= slv_sel_t'((int'(select_idx) + 1) % NumSlvPorts);
          end else if (select_valid && !select_write && mst_resp_i.ar_ready) begin
            active_q <= select_idx;
            state_q  <= StateReadResp;
            rr_q     <= slv_sel_t'((int'(select_idx) + 1) % NumSlvPorts);
          end
        end

        StateWriteResp: begin
          if (mst_resp_i.b_valid && slv_reqs_i[active_q].b_ready) begin
            state_q <= StateIdle;
          end
        end

        StateReadResp: begin
          if (mst_resp_i.r_valid && slv_reqs_i[active_q].r_ready) begin
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
  initial begin
    assert (NumSlvPorts > 0) else $fatal(1, "soc_axi_arbiter: NumSlvPorts must be non-zero");
  end
`endif
endmodule
