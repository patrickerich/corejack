module soc_axi_to_mem
  import axi_pkg::*;
  import soc_bus_pkg::*;
#(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = soc_bus_pkg::AxiDataWidth
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  soc_bus_pkg::soc_axi_req_t  s_axi_req_i,
  output soc_bus_pkg::soc_axi_resp_t s_axi_rsp_o,

  output logic                       mem_req_o,
  output logic                       mem_we_o,
  output logic [AddrWidth-1:0]       mem_addr_o,
  output logic [DataWidth-1:0]       mem_wdata_o,
  output logic [DataWidth/8-1:0]     mem_be_o,
  input  logic                       mem_gnt_i,
  input  logic                       mem_rvalid_i,
  output logic                       mem_rready_o,
  input  logic [DataWidth-1:0]       mem_rdata_i,
  input  logic                       mem_err_i
);
  typedef enum logic [2:0] {
    StateIdle,
    StateWriteCollect,
    StateWriteMem,
    StateWriteWait,
    StateWriteResp,
    StateReadMem,
    StateReadWait,
    StateReadResp
  } state_e;

  state_e state_q;
  soc_bus_pkg::soc_axi_aw_chan_t aw_q;
  soc_bus_pkg::soc_axi_w_chan_t  w_q;
  soc_bus_pkg::soc_axi_ar_chan_t ar_q;
  soc_bus_pkg::soc_axi_r_chan_t  r_q;
  soc_bus_pkg::soc_axi_b_chan_t  b_q;
  logic                          have_aw_q;
  logic                          have_w_q;

  always_comb begin
    s_axi_rsp_o = '0;
    mem_req_o   = 1'b0;
    mem_we_o    = 1'b0;
    mem_addr_o  = '0;
    mem_wdata_o = '0;
    mem_be_o    = '0;
    mem_rready_o = 1'b0;

    unique case (state_q)
      StateIdle: begin
        s_axi_rsp_o.aw_ready = s_axi_req_i.aw_valid && !s_axi_req_i.ar_valid;
        s_axi_rsp_o.w_ready  = s_axi_req_i.w_valid && !s_axi_req_i.ar_valid;
        s_axi_rsp_o.ar_ready = !s_axi_req_i.aw_valid && !s_axi_req_i.w_valid;
      end

      StateWriteCollect: begin
        s_axi_rsp_o.aw_ready = !have_aw_q;
        s_axi_rsp_o.w_ready  = !have_w_q;
      end

      StateWriteMem: begin
        mem_req_o   = 1'b1;
        mem_we_o    = 1'b1;
        mem_addr_o  = AddrWidth'(aw_q.addr);
        mem_wdata_o = DataWidth'(w_q.data);
        mem_be_o    = w_q.strb[DataWidth/8-1:0];
      end

      StateWriteWait: begin
        mem_rready_o = 1'b1;
      end

      StateWriteResp: begin
        s_axi_rsp_o.b_valid = 1'b1;
        s_axi_rsp_o.b       = b_q;
      end

      StateReadMem: begin
        mem_req_o    = 1'b1;
        mem_we_o     = 1'b0;
        mem_addr_o   = AddrWidth'(ar_q.addr);
        mem_be_o     = '1;
        mem_rready_o = 1'b1;
      end

      StateReadWait: begin
        mem_rready_o = 1'b1;
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
      state_q   <= StateIdle;
      aw_q      <= '0;
      w_q       <= '0;
      ar_q      <= '0;
      r_q       <= '0;
      b_q       <= '0;
      have_aw_q <= 1'b0;
      have_w_q  <= 1'b0;
    end else begin
      unique case (state_q)
        StateIdle: begin
          have_aw_q <= 1'b0;
          have_w_q  <= 1'b0;

          if (s_axi_rsp_o.ar_ready && s_axi_req_i.ar_valid) begin
            ar_q    <= s_axi_req_i.ar;
            state_q <= StateReadMem;
          end else if ((s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid) ||
                       (s_axi_rsp_o.w_ready  && s_axi_req_i.w_valid)) begin
            if (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid) begin
              aw_q      <= s_axi_req_i.aw;
              have_aw_q <= 1'b1;
            end
            if (s_axi_rsp_o.w_ready && s_axi_req_i.w_valid) begin
              w_q      <= s_axi_req_i.w;
              have_w_q <= 1'b1;
            end
            if ((s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid) &&
                (s_axi_rsp_o.w_ready  && s_axi_req_i.w_valid)) begin
              state_q <= StateWriteMem;
            end else begin
              state_q <= StateWriteCollect;
            end
          end
        end

        StateWriteCollect: begin
          if (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid) begin
            aw_q      <= s_axi_req_i.aw;
            have_aw_q <= 1'b1;
          end
          if (s_axi_rsp_o.w_ready && s_axi_req_i.w_valid) begin
            w_q      <= s_axi_req_i.w;
            have_w_q <= 1'b1;
          end
          if ((have_aw_q || (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid)) &&
              (have_w_q  || (s_axi_rsp_o.w_ready  && s_axi_req_i.w_valid))) begin
            state_q <= StateWriteMem;
          end
        end

        StateWriteMem: begin
          if (mem_req_o && mem_gnt_i) begin
            state_q <= StateWriteWait;
          end
        end

        StateWriteWait: begin
          if (mem_rvalid_i) begin
            state_q  <= StateWriteResp;
            b_q.id   <= aw_q.id;
            b_q.resp <= mem_err_i ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
            b_q.user <= '0;
          end
        end

        StateWriteResp: begin
          if (s_axi_req_i.b_ready) begin
            state_q <= StateIdle;
          end
        end

        StateReadMem: begin
          if (mem_req_o && mem_gnt_i) begin
            state_q <= StateReadWait;
          end
        end

        StateReadWait: begin
          if (mem_rvalid_i) begin
            r_q.id   <= ar_q.id;
            r_q.data <= DataWidth'(mem_rdata_i);
            r_q.resp <= mem_err_i ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY;
            r_q.last <= 1'b1;
            r_q.user <= '0;
            state_q  <= StateReadResp;
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

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (s_axi_rsp_o.b_valid && !s_axi_req_i.b_ready) begin
        assert (s_axi_rsp_o.b == b_q);
      end
      if (s_axi_rsp_o.r_valid && !s_axi_req_i.r_ready) begin
        assert (s_axi_rsp_o.r == r_q);
      end
      if (state_q == StateWriteMem) begin
        assert (aw_q.len == '0);
        assert (w_q.last);
      end
      if (state_q == StateReadMem) begin
        assert (ar_q.len == '0);
      end
    end
  end
`endif
endmodule
