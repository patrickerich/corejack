module soc_axi_to_dm #(
  parameter logic [31:0] BaseAddr = 32'h0,
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

  input  axi_req_t                   s_axi_req_i,
  output axi_resp_t                  s_axi_rsp_o,
  output logic                       dm_req_o,
  output logic                       dm_we_o,
  output logic [63:0]                dm_addr_o,
  output logic [7:0]                 dm_be_o,
  output logic [63:0]                dm_wdata_o,
  input  logic [63:0]                dm_rdata_i
);
  import axi_pkg::*;

  typedef enum logic [2:0] {
    StateIdle,
    StateAccess,
    StateReadCapture,
    StateWriteResp,
    StateReadResp
  } state_e;

  state_e state_q;
  axi_aw_chan_t aw_q;
  axi_w_chan_t  w_q;
  axi_ar_chan_t ar_q;
  axi_b_chan_t  b_q;
  axi_r_chan_t  r_q;
  logic         op_write_q;
  // Round-robin tie-break between a pending read and a pending write so
  // neither starves. A write only competes once both AW and W are valid
  // (this adapter captures them together and has no collect state).
  // 1 => a read wins a simultaneous read/write tie.
  logic         rr_prefer_read_q;
  logic         rd_req;
  logic         wr_req;
  logic         arb_read;

  assign rd_req   = s_axi_req_i.ar_valid;
  assign wr_req   = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
  assign arb_read = rd_req && (!wr_req || rr_prefer_read_q);

  always_comb begin
    s_axi_rsp_o = '0;
    dm_req_o    = (state_q == StateAccess);
    dm_we_o     = op_write_q;
    dm_addr_o   = 64'((op_write_q ? aw_q.addr[31:0] : ar_q.addr[31:0]) - BaseAddr);
    dm_be_o     = op_write_q ? w_q.strb : 8'hFF;
    dm_wdata_o  = w_q.data;

    unique case (state_q)
      StateIdle: begin
        // Serve exactly one side, chosen by arb_read. Gating each channel on
        // the other's valid would leave both readies low forever when the
        // crossbar presents a read and a write in the same cycle - see the
        // identical fix in soc_axi_to_mem.
        if (arb_read) begin
          s_axi_rsp_o.ar_ready = 1'b1;
        end else begin
          s_axi_rsp_o.aw_ready = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
          s_axi_rsp_o.w_ready  = s_axi_req_i.aw_valid && s_axi_req_i.w_valid;
        end
      end

      StateWriteResp: begin
        s_axi_rsp_o.b_valid = 1'b1;
        s_axi_rsp_o.b       = b_q;
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
      state_q    <= StateIdle;
      aw_q       <= '0;
      w_q        <= '0;
      ar_q       <= '0;
      b_q        <= '0;
      r_q        <= '0;
      op_write_q <= 1'b0;
      rr_prefer_read_q <= 1'b1;
    end else begin
      unique case (state_q)
        StateIdle: begin
          if (s_axi_rsp_o.aw_ready && s_axi_req_i.aw_valid && s_axi_req_i.w_valid) begin
            aw_q       <= s_axi_req_i.aw;
            w_q        <= s_axi_req_i.w;
            op_write_q <= 1'b1;
            rr_prefer_read_q <= 1'b1;  // serving a write; favor a read next
            state_q    <= StateAccess;
          end else if (s_axi_rsp_o.ar_ready && s_axi_req_i.ar_valid) begin
            ar_q       <= s_axi_req_i.ar;
            op_write_q <= 1'b0;
            rr_prefer_read_q <= 1'b0;  // just served a read; favor a write next
            state_q    <= StateAccess;
          end
        end

        StateAccess: begin
          if (op_write_q) begin
            b_q.id   <= aw_q.id;
            b_q.resp <= axi_pkg::RESP_OKAY;
            b_q.user <= '0;
            state_q  <= StateWriteResp;
          end else begin
            state_q <= StateReadCapture;
          end
        end

        StateReadCapture: begin
          r_q.id   <= ar_q.id;
          r_q.data <= dm_rdata_i;
          r_q.resp <= axi_pkg::RESP_OKAY;
          r_q.last <= 1'b1;
          r_q.user <= '0;
          state_q  <= StateReadResp;
        end

        StateWriteResp: begin
          if (s_axi_req_i.b_ready) begin
            state_q <= StateIdle;
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
endmodule
