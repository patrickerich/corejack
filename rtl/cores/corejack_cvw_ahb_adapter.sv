// SPDX-License-Identifier: Apache-2.0
//
module corejack_cvw_ahb_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0080
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,

  output logic        instr_req_o,
  input  logic        instr_gnt_i,
  input  logic        instr_rvalid_i,
  output logic [31:0] instr_addr_o,
  input  logic [31:0] instr_rdata_i,
  input  logic        instr_err_i,

  output logic        data_req_o,
  input  logic        data_gnt_i,
  input  logic        data_rvalid_i,
  output logic        data_we_o,
  output logic [3:0]  data_be_o,
  output logic [31:0] data_addr_o,
  output logic [31:0] data_wdata_o,
  input  logic [31:0] data_rdata_i,
  input  logic        data_err_i,

  output logic        core_sleep_o
);
  import cvw::*;

`include "config.vh"
`include "parameter-defs.vh"

  // The Wally config header freezes RESET_VECTOR; rebind it to the platform
  // BootAddr so a board/descriptor that moves RAM cannot leave CVW booting at
  // a stale address.
  function automatic cvw_t cvw_with_boot_addr(input cvw_t p, input logic [31:0] boot);
    cvw_t r;
    r = p;
    r.RESET_VECTOR = {32'h0, boot};
    return r;
  endfunction

  localparam cvw_t PCfg = cvw_with_boot_addr(P, BootAddr);

  typedef enum logic [2:0] {
    StateIdle,
    StateWriteData,
    StateIssue,
    StateWaitRsp,
    StateErrFirst,
    StateRsp
  } state_e;

  state_e                  state_q;
  logic [P.PA_BITS-1:0]    haddr;
  logic [31:0] hwdata;
  logic [3:0]  hwstrb;
  logic        hwrite;
  logic [2:0]  hsize;
  logic [2:0]  hburst;
  logic [3:0]  hprot;
  logic [1:0]  htrans;
  logic        hmastlock;
  logic [31:0] hrdata;
  logic        hready;
  logic        hresp;
  logic        hclk_unused;
  logic        hresetn_unused;

  logic [31:0] addr_q;
  logic [31:0] wdata_q;
  logic [3:0]  be_q;
  logic        we_q;
  logic [31:0] rdata_q;
  logic        err_q;

  function automatic logic [3:0] ahb_be(
    input logic [1:0] addr,
    input logic [2:0] size
  );
    unique case (size)
      3'b000: return 4'b0001 << addr;
      3'b001: return addr[1] ? 4'b1100 : 4'b0011;
      default: return 4'b1111;
    endcase
  endfunction

  logic ahb_active;
  logic accept_addr;
  logic rsp_seen;

  assign ahb_active  = htrans[1];
  assign accept_addr = ((state_q == StateIdle) || (state_q == StateRsp)) && ahb_active;
  assign rsp_seen    = data_rvalid_i;

  assign instr_req_o  = 1'b0;
  assign instr_addr_o = '0;

  assign data_req_o   = (state_q == StateIssue);
  assign data_we_o    = we_q;
  assign data_be_o    = be_q;
  assign data_addr_o  = addr_q;
  assign data_wdata_o = wdata_q;

  // AHB error responses take the mandated two cycles: HRESP high with HREADY
  // low first (StateErrFirst), then HRESP high with HREADY high (StateRsp).
  // Wally's EBU currently ignores HRESP, but any compliant master must see
  // the two-cycle form.
  assign hready = (state_q == StateIdle) || (state_q == StateRsp);
  assign hresp  = err_q;
  assign hrdata = rdata_q;

  assign core_sleep_o = 1'b0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      addr_q  <= '0;
      wdata_q <= '0;
      be_q    <= '0;
      we_q    <= 1'b0;
      rdata_q <= '0;
      err_q   <= 1'b0;
    end else begin
      unique case (state_q)
        StateIdle, StateRsp: begin
          err_q <= 1'b0;
          if (accept_addr) begin
            addr_q <= haddr[31:0];
            be_q   <= ahb_be(haddr[1:0], hsize);
            we_q   <= hwrite;
            if (hwrite) begin
              state_q <= StateWriteData;
            end else begin
              wdata_q <= '0;
              state_q <= StateIssue;
            end
          end else begin
            state_q <= StateIdle;
          end
        end

        StateWriteData: begin
          wdata_q <= hwdata;
          state_q <= StateIssue;
        end

        StateIssue: begin
          if (data_gnt_i) begin
            state_q <= StateWaitRsp;
          end
        end

        StateWaitRsp: begin
          if (rsp_seen) begin
            rdata_q <= we_q ? '0 : data_rdata_i;
            err_q   <= data_err_i;
            state_q <= data_err_i ? StateErrFirst : StateRsp;
          end
        end

        StateErrFirst: begin
          state_q <= StateRsp;
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
      if (instr_err_i && instr_rvalid_i) begin
        $fatal(1, "CVW instruction path should be unused");
      end
      if (instr_gnt_i && instr_req_o) begin
        $fatal(1, "CVW instruction path should be unused");
      end
    end
  end
`endif

  wallypipelinedcore #(
    .P (PCfg)
  ) i_cvw (
    .clk           (clk_i),
    .reset         (!rst_ni),
    .MTimerInt     (irq_timer_i),
    .MExtInt       (irq_external_i),
    .SExtInt       (1'b0),
    .MSwInt        (irq_software_i),
    // KNOWN LIMITATION: Wally shadows the CLINT's memory-mapped mtime through
    // this port for the time/timeh CSRs (rdtime), but the platform's vendored
    // PULP CLINT does not export its mtime counter, so rdtime reads 0 on CVW.
    // Software must use the memory-mapped mtime at 0x0200_bff8 instead. See
    // docs/source/open_items.md.
    .MTIME_CLINT   (64'h0),
    .HRDATA        (hrdata),
    .HREADY        (hready),
    .HRESP         (hresp),
    .HCLK          (hclk_unused),
    .HRESETn       (hresetn_unused),
    .HADDR         (haddr),
    .HWDATA        (hwdata),
    .HWSTRB        (hwstrb),
    .HWRITE        (hwrite),
    .HSIZE         (hsize),
    .HBURST        (hburst),
    .HPROT         (hprot),
    .HTRANS        (htrans),
    .HMASTLOCK     (hmastlock),
    .ExternalStall (1'b0)
  );

  logic unused;
  assign unused = ^{
    instr_gnt_i,
    instr_rvalid_i,
    instr_rdata_i,
    instr_err_i,
    hwstrb,
    hburst,
    hprot,
    hmastlock,
    hclk_unused,
    hresetn_unused
  };
endmodule
