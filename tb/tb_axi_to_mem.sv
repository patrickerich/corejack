// SPDX-License-Identifier: Apache-2.0
//
// Self-checking testbench for soc_axi_to_mem driving two soc_mem_ss 64-bit
// ports (read engine -> port 0, write engine -> port 1), the shape of the iDMA
// and CVA6 RAM legs in soc_top. The unit harness in axi_adapter_dut merges the
// two memory ports; this bench keeps them independent so the engines can
// backpressure each other through soc_mem_ss.
//
// Phases:
//   1. preload  - write the source region with no stalls (write throughput);
//   2. read     - read it back with no stalls (read throughput);
//   3. random   - random reads of the source region and writes to a scratch
//                 region, random IDs, random AR/AW gaps, W lagging AW (as
//                 CVA6 may present it), random and long R/B stalls, and
//                 out-of-range accesses that must return SLVERR;
//   4. copy     - an iDMA-style copy: R data feeds a CopyBuf-deep write
//                 buffer and RREADY is withheld while it is full, first with
//                 no stalls (copy throughput), then with random B stalls;
//   5. verify   - read back the scratch and destination regions.
//
// Checks: every R/B response arrives in admission order with the right ID,
// response code and data, and nothing is left outstanding; the bridge's own
// assertions (conservation, single beat) and soc_axi_protocol_checker (held
// valid and stable payload while stalled) run throughout. A phase that does
// not drain within its budget fails the run.
//
// Run with `make sv-tb TB=tb_axi_to_mem` (Verilator --binary --timing); the
// run exits nonzero on failure. Defines:
//   TB_MAX_OUT, TB_REQ_DEPTH, TB_RSP_DEPTH - override the bridge parameters,
//                                            which default to soc_top's sizing
//                                            (mem_ss_pkg) for sweeps;
//   MEMIMPL_XILINX                         - select the Xilinx SRAM slice.

`ifndef TB_MAX_OUT
`define TB_MAX_OUT mem_ss_pkg::mem_bridge_outstanding(MemImpl)
`endif
`ifndef TB_REQ_DEPTH
`define TB_REQ_DEPTH mem_ss_pkg::MemBridgeQueueDepth
`endif
`ifndef TB_RSP_DEPTH
`define TB_RSP_DEPTH mem_ss_pkg::MemBridgeQueueDepth
`endif

module tb_axi_to_mem;
  import soc_bus_pkg::*;

`ifdef MEMIMPL_XILINX
  localparam mem_ss_pkg::mem_impl_e MemImpl = mem_ss_pkg::MemImplXilinx;
`else
  localparam mem_ss_pkg::mem_impl_e MemImpl = mem_ss_pkg::MemImplModel;
`endif

  localparam int unsigned MaxOut       = `TB_MAX_OUT;
  localparam int unsigned ReqDepth     = `TB_REQ_DEPTH;
  localparam int unsigned RspDepth     = `TB_RSP_DEPTH;
  localparam int unsigned NumBanks     = 8;
  localparam int unsigned WordsPerBank = 256;
  localparam int unsigned TotalWords   = NumBanks * WordsPerBank;  // 2048
  localparam logic [31:0] BaseAddr     = 32'h8000_0000;
  localparam int unsigned CopyBuf      = 3;                        // iDMA BufferDepth

  // 64-bit word regions.
  localparam int unsigned SrcBase = 0;
  localparam int unsigned SrcWords = 1024;
  localparam int unsigned ScrBase = 1024;
  localparam int unsigned ScrWords = 512;
  localparam int unsigned DstBase = 1536;
  localparam int unsigned DstWords = 512;

  localparam int unsigned RandomOps = 6000;

  logic clk, rst_n;
  initial clk = 1'b0;
  always #5 clk = ~clk;

  soc_axi_req_t  axi_req;
  soc_axi_resp_t axi_rsp;

  logic [1:0]       req64, gnt64, we64, rvalid64, rready64, err64;
  logic [1:0][31:0] addr64;
  logic [1:0][63:0] wdata64, rdata64;
  logic [1:0][7:0]  be64;

  soc_axi_to_mem #(
    .AddrWidth      (32),
    .DataWidth      (64),
    .MaxOutstanding (MaxOut),
    .ReqDepth       (ReqDepth),
    .RspDepth       (RspDepth)
  ) dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .s_axi_req_i     (axi_req),
    .s_axi_rsp_o     (axi_rsp),
    .mem_rd_req_o    (req64[0]),
    .mem_rd_we_o     (we64[0]),
    .mem_rd_addr_o   (addr64[0]),
    .mem_rd_wdata_o  (wdata64[0]),
    .mem_rd_be_o     (be64[0]),
    .mem_rd_gnt_i    (gnt64[0]),
    .mem_rd_rvalid_i (rvalid64[0]),
    .mem_rd_rready_o (rready64[0]),
    .mem_rd_rdata_i  (rdata64[0]),
    .mem_rd_err_i    (err64[0]),
    .mem_wr_req_o    (req64[1]),
    .mem_wr_we_o     (we64[1]),
    .mem_wr_addr_o   (addr64[1]),
    .mem_wr_wdata_o  (wdata64[1]),
    .mem_wr_be_o     (be64[1]),
    .mem_wr_gnt_i    (gnt64[1]),
    .mem_wr_rvalid_i (rvalid64[1]),
    .mem_wr_rready_o (rready64[1]),
    .mem_wr_err_i    (err64[1])
  );

  soc_mem_ss #(
    .NumPorts32   (0),
    .NumPorts64   (2),
    .NumBanks     (NumBanks),
    .WordsPerBank (WordsPerBank),
    .BaseAddr     (BaseAddr),
    .MemImpl      (MemImpl)
  ) i_mem_ss (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .req32_i    ('0),
    .gnt32_o    (),
    .we32_i     ('0),
    .addr32_i   ('0),
    .wdata32_i  ('0),
    .be32_i     ('0),
    .rvalid32_o (),
    .rready32_i ('0),
    .rdata32_o  (),
    .err32_o    (),
    .req64_i    (req64),
    .gnt64_o    (gnt64),
    .we64_i     (we64),
    .addr64_i   (addr64),
    .wdata64_i  (wdata64),
    .be64_i     (be64),
    .rvalid64_o (rvalid64),
    .rready64_i (rready64),
    .rdata64_o  (rdata64),
    .err64_o    (err64)
  );

  soc_axi_protocol_checker i_checker (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .req_i  (axi_req),
    .rsp_i  (axi_rsp)
  );

  // ---------------------------------------------------------------------------
  // Stimulus queues, expectations and knobs.
  // ---------------------------------------------------------------------------
  typedef struct {
    logic [3:0]  id;
    logic [31:0] addr;
    logic [63:0] data;
  } item_t;

  typedef struct {
    logic [3:0]  id;
    bit          err;
    logic [31:0] addr;
    logic [63:0] data;
  } exp_t;

  item_t ar_q[$];
  item_t aw_q[$];
  exp_t  r_exp[$];
  exp_t  b_exp[$];
  logic [63:0] ref_mem [TotalWords];

  int unsigned ar_gap_pct, aw_gap_pct, w_lag_pct, r_stall_pct, b_stall_pct;
  bit          long_stalls;
  bit          copy_mode;
  int unsigned copy_offset;  // destination word = source word + copy_offset

  int unsigned errors;
  longint unsigned cyc;
  bit ar_fired, aw_fired;
  int unsigned long_stall_left;

  // Per-phase throughput bookkeeping (first and last R/B handshake cycle).
  int unsigned     n_r, n_b;
  longint unsigned r_first, r_last, b_first, b_last;

  function automatic bit out_of_range(logic [31:0] addr);
    return (addr < BaseAddr) || (addr >= BaseAddr + TotalWords * 8);
  endfunction

  function automatic int unsigned word_of(logic [31:0] addr);
    return (addr - BaseAddr) / 8;
  endfunction

  // ---------------------------------------------------------------------------
  // Bus process: drive after the falling edge, sample handshakes just before
  // the rising edge, so both sides see settled values.
  // ---------------------------------------------------------------------------
  always begin : bus
    @(negedge clk);
    if (!rst_n) begin
      axi_req         = '0;
      ar_fired        = 1'b0;
      aw_fired        = 1'b0;
      long_stall_left = 0;
    end else begin
      cyc++;

      // AR: hold a stalled request, otherwise load the next one.
      if (!axi_req.ar_valid || ar_fired) begin
        axi_req.ar_valid = 1'b0;
        if ((ar_q.size() != 0) && ($urandom_range(99) >= ar_gap_pct)) begin
          item_t it;
          it = ar_q.pop_front();
          axi_req.ar_valid = 1'b1;
          axi_req.ar       = '0;
          axi_req.ar.id    = it.id;
          axi_req.ar.addr  = AxiAddrWidth'(it.addr);
          axi_req.ar.size  = 3'd3;
          axi_req.ar.burst = axi_pkg::BURST_INCR;
        end
      end

      // AW + W. W carries the same item; with w_lag_pct it may trail AW by some
      // cycles, and once raised it is held until the write is accepted.
      if (axi_req.aw_valid && !aw_fired && !axi_req.w_valid) begin
        axi_req.w_valid = ($urandom_range(99) >= w_lag_pct);
      end
      if (!axi_req.aw_valid || aw_fired) begin
        axi_req.aw_valid = 1'b0;
        axi_req.w_valid  = 1'b0;
        if ((aw_q.size() != 0) && ($urandom_range(99) >= aw_gap_pct)) begin
          item_t it;
          it = aw_q.pop_front();
          axi_req.aw_valid = 1'b1;
          axi_req.aw       = '0;
          axi_req.aw.id    = it.id;
          axi_req.aw.addr  = AxiAddrWidth'(it.addr);
          axi_req.aw.size  = 3'd3;
          axi_req.aw.burst = axi_pkg::BURST_INCR;
          axi_req.w_valid  = ($urandom_range(99) >= w_lag_pct);
          axi_req.w        = '0;
          axi_req.w.data   = it.data;
          axi_req.w.strb   = '1;
          axi_req.w.last   = 1'b1;
        end
      end

      // Occasional long R/B stalls on top of the random ones.
      if (long_stall_left != 0) begin
        long_stall_left--;
      end else if (long_stalls && ($urandom_range(299) == 0)) begin
        long_stall_left = 20 + $urandom_range(40);
      end

      axi_req.r_ready = (long_stall_left == 0) && ($urandom_range(99) >= r_stall_pct);
      // iDMA coupling: stop reading while the write buffer is full.
      if (copy_mode && ((aw_q.size() + int'(axi_req.aw_valid)) >= CopyBuf)) begin
        axi_req.r_ready = 1'b0;
      end
      axi_req.b_ready = (long_stall_left == 0) && ($urandom_range(99) >= b_stall_pct);

      #4;

      ar_fired = axi_req.ar_valid && axi_rsp.ar_ready;
      aw_fired = axi_req.aw_valid && axi_rsp.aw_ready;
      if (axi_rsp.aw_ready && !axi_req.w_valid) begin
        $error("AW accepted without W (addr %08h)", 32'(axi_req.aw.addr));
        errors++;
      end
      if (axi_rsp.aw_ready != axi_rsp.w_ready) begin
        $error("aw_ready %b != w_ready %b", axi_rsp.aw_ready, axi_rsp.w_ready);
        errors++;
      end

      if (ar_fired) begin
        logic [31:0] a;
        a = 32'(axi_req.ar.addr);
        if (out_of_range(a)) begin
          r_exp.push_back('{id: axi_req.ar.id, err: 1'b1, addr: a, data: '0});
        end else begin
          r_exp.push_back('{id: axi_req.ar.id, err: 1'b0, addr: a,
                            data: ref_mem[word_of(a)]});
        end
      end

      if (aw_fired) begin
        logic [31:0] a;
        a = 32'(axi_req.aw.addr);
        if (!out_of_range(a)) ref_mem[word_of(a)] = axi_req.w.data;
        b_exp.push_back('{id: axi_req.aw.id, err: out_of_range(a), addr: a, data: '0});
      end

      if (axi_rsp.r_valid && axi_req.r_ready) begin
        exp_t e;
        if (r_exp.size() == 0) begin
          $error("unexpected R (id %0h)", axi_rsp.r.id);
          errors++;
        end else begin
          e = r_exp.pop_front();
          if (axi_rsp.r.id !== e.id) begin
            $error("R id %0h exp %0h (addr %08h)", axi_rsp.r.id, e.id, e.addr);
            errors++;
          end
          if (axi_rsp.r.resp !== (e.err ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY)) begin
            $error("R resp %0d exp err=%0b (addr %08h)", axi_rsp.r.resp, e.err, e.addr);
            errors++;
          end
          if (!e.err && (axi_rsp.r.data !== e.data)) begin
            $error("R data %016h exp %016h (addr %08h)", axi_rsp.r.data, e.data, e.addr);
            errors++;
          end
          if (!axi_rsp.r.last) begin
            $error("R last not set");
            errors++;
          end
          if (copy_mode && !e.err) begin
            aw_q.push_back('{id: e.id, addr: e.addr + 32'(copy_offset * 8),
                             data: axi_rsp.r.data});
          end
        end
        if (n_r == 0) r_first = cyc;
        r_last = cyc;
        n_r++;
      end

      if (axi_rsp.b_valid && axi_req.b_ready) begin
        exp_t e;
        if (b_exp.size() == 0) begin
          $error("unexpected B (id %0h)", axi_rsp.b.id);
          errors++;
        end else begin
          e = b_exp.pop_front();
          if (axi_rsp.b.id !== e.id) begin
            $error("B id %0h exp %0h (addr %08h)", axi_rsp.b.id, e.id, e.addr);
            errors++;
          end
          if (axi_rsp.b.resp !== (e.err ? axi_pkg::RESP_SLVERR : axi_pkg::RESP_OKAY)) begin
            $error("B resp %0d exp err=%0b (addr %08h)", axi_rsp.b.resp, e.err, e.addr);
            errors++;
          end
        end
        if (n_b == 0) b_first = cyc;
        b_last = cyc;
        n_b++;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Phase control.
  // ---------------------------------------------------------------------------
  task automatic set_knobs(int unsigned ar_gap, int unsigned aw_gap, int unsigned w_lag,
                           int unsigned r_stall, int unsigned b_stall, bit long_stall);
    ar_gap_pct  = ar_gap;
    aw_gap_pct  = aw_gap;
    w_lag_pct   = w_lag;
    r_stall_pct = r_stall;
    b_stall_pct = b_stall;
    long_stalls = long_stall;
  endtask

  task automatic start_phase();
    n_r = 0;
    n_b = 0;
  endtask

  // Wait until every queue, expectation and in-flight request has drained.
  task automatic drain(string name, int unsigned budget);
    int unsigned t;
    t = 0;
    while ((ar_q.size() != 0) || (aw_q.size() != 0) || (r_exp.size() != 0) ||
           (b_exp.size() != 0) || axi_req.ar_valid || axi_req.aw_valid) begin
      @(posedge clk);
      t++;
      if (t > budget) begin
        $error("%s: did not drain in %0d cycles (ar_q %0d aw_q %0d r_exp %0d b_exp %0d)",
               name, budget, ar_q.size(), aw_q.size(), r_exp.size(), b_exp.size());
        $fatal(1, "TB_AXI_TO_MEM: FAIL (%s timeout)", name);
      end
    end
    repeat (4) @(posedge clk);
  endtask

  function automatic string rate(int unsigned n, longint unsigned first, longint unsigned last);
    real r;
    if (n < 2) return "n/a";
    r = real'(n) / real'(last - first + 1);
    return $sformatf("%0d in %0d cycles = %0.3f/cycle", n, last - first + 1, r);
  endfunction

  initial begin : control
    errors  = 0;
    cyc     = 0;
    copy_mode = 1'b0;
    copy_offset = 0;
    set_knobs(0, 0, 0, 0, 0, 1'b0);
    for (int unsigned w = 0; w < TotalWords; w++) ref_mem[w] = '0;

    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    $display("TB_AXI_TO_MEM: MaxOutstanding=%0d ReqDepth=%0d RspDepth=%0d ReadLat=%0d",
             MaxOut, ReqDepth, RspDepth, mem_ss_pkg::mem_read_latency(MemImpl));

    // 1. Preload the source region.
    start_phase();
    for (int unsigned w = 0; w < SrcWords; w++) begin
      aw_q.push_back('{id: 4'(w), addr: BaseAddr + 32'((SrcBase + w) * 8),
                       data: {32'hA5A5_0000 | 32'(w), 32'h5A5A_0000 | 32'(w)}});
    end
    drain("preload", 20000);
    $display("  preload writes: %s", rate(n_b, b_first, b_last));

    // 2. Saturated reads.
    start_phase();
    for (int unsigned w = 0; w < SrcWords; w++) begin
      ar_q.push_back('{id: 4'(w * 3), addr: BaseAddr + 32'((SrcBase + w) * 8), data: '0});
    end
    drain("read", 20000);
    $display("  saturated reads: %s", rate(n_r, r_first, r_last));

    // 3. Random traffic with stalls and errors.
    start_phase();
    set_knobs(30, 30, 60, 40, 40, 1'b1);
    for (int unsigned i = 0; i < RandomOps; i++) begin
      logic [31:0] ra, wa;
      ra = ($urandom_range(31) == 0) ?
           BaseAddr + 32'(TotalWords * 8) + 32'($urandom_range(15) * 8) :
           BaseAddr + 32'((SrcBase + $urandom_range(SrcWords - 1)) * 8);
      wa = ($urandom_range(31) == 0) ?
           BaseAddr + 32'(TotalWords * 8) + 32'($urandom_range(15) * 8) :
           BaseAddr + 32'((ScrBase + $urandom_range(ScrWords - 1)) * 8);
      ar_q.push_back('{id: 4'($urandom), addr: ra, data: '0});
      aw_q.push_back('{id: 4'($urandom), addr: wa, data: {$urandom, $urandom}});
    end
    drain("random", 400000);
    $display("  random: %0d R and %0d B responses checked", n_r, n_b);

    // 4a. iDMA-style copy, no external stalls.
    start_phase();
    set_knobs(0, 0, 0, 0, 0, 1'b0);
    copy_mode   = 1'b1;
    copy_offset = DstBase - SrcBase;
    for (int unsigned w = 0; w < DstWords / 2; w++) begin
      ar_q.push_back('{id: 4'h0, addr: BaseAddr + 32'((SrcBase + w) * 8), data: '0});
    end
    drain("copy", 20000);
    $display("  copy reads: %s, writes: %s", rate(n_r, r_first, r_last),
             rate(n_b, b_first, b_last));

    // 4b. Copy with random B stalls and long stalls (coupling under pressure).
    start_phase();
    set_knobs(0, 0, 0, 0, 50, 1'b1);
    for (int unsigned w = DstWords / 2; w < DstWords; w++) begin
      ar_q.push_back('{id: 4'h0, addr: BaseAddr + 32'((SrcBase + w) * 8), data: '0});
    end
    drain("copy-stalled", 200000);
    copy_mode = 1'b0;
    $display("  stalled copy: %0d R and %0d B responses checked", n_r, n_b);

    // 5. Read back the scratch and destination regions.
    start_phase();
    set_knobs(10, 10, 30, 20, 20, 1'b0);
    for (int unsigned w = ScrBase; w < DstBase + DstWords; w++) begin
      ar_q.push_back('{id: 4'($urandom), addr: BaseAddr + 32'(w * 8), data: '0});
    end
    drain("verify", 100000);
    for (int unsigned w = 0; w < DstWords; w++) begin
      if (ref_mem[DstBase + w] !== ref_mem[SrcBase + w]) begin
        $error("copy mismatch at word %0d", w);
        errors++;
      end
    end

    if (errors == 0) $display("TB_AXI_TO_MEM: PASS");
    else             $fatal(1, "TB_AXI_TO_MEM: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
