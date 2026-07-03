// Throughput benchmark harness for soc_mem_ss.
//
// Instantiates soc_mem_ss with a configurable number of 64-bit init ports and
// banks, and drives each port with a pipelined, multi-outstanding traffic
// generator. cocotb selects the access pattern and which ports are active, runs
// a fixed per-port access budget, and reads back the cycle count and the number
// of completed accesses to compute aggregate words/cycle.
//
// Patterns (pattern_i):
//   0 - disjoint banks: port p only ever touches bank p%NumBanks (best case,
//       no inter-port bank conflict) -> shows the concurrency ceiling.
//   1 - same bank:      every port hammers bank 0 (worst case) -> shows full
//       serialization at one slice.
//   2 - random:         per-port LFSR addresses across the whole RAM window.
//
// Each generator holds its request asserted until its budget has been issued and
// lets the port's req/gnt handshake throttle it, so a port runs as many
// outstanding requests as the subsystem will accept (bounded by the per-port
// egress reorder-buffer depth). This measures the redesigned subsystem's actual
// throughput ceiling, which - unlike the old single-cycle design - is bounded by
// the per-port outstanding depth and the per-bank slice-pipeline rate (see
// docs/mem_ss_redesign.md section 5). All traffic is 64-bit; the subsystem's
// 32-bit port group is unused here (NumPorts32 = 0).
module mem_ss_bench_dut
  import mem_ss_pkg::*;
#(
  parameter int unsigned NumInitPorts    = 4,
  parameter int unsigned NumBanks        = 4,
  parameter int unsigned NumWordsPerBank  = 256,
  parameter int unsigned DataWidth       = 64,
  parameter int unsigned AddrWidth       = 32,
  parameter logic [AddrWidth-1:0] BaseAddr = 32'h8000_0000,
  parameter int unsigned MaxCycles       = 200_000
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Control (driven by cocotb).
  input  logic                    start_i,       // pulse to (re)start a run
  input  logic [1:0]              pattern_i,
  input  logic                    we_i,          // 0 = reads, 1 = writes
  input  logic [31:0]             budget_i,      // accesses per active port
  input  logic [NumInitPorts-1:0] active_mask_i,

  // Status (read by cocotb).
  output logic        running_o,
  output logic        done_o,
  output logic        timeout_o,
  output logic [63:0] cycles_o,
  output logic [63:0] accesses_o,
  output logic [31:0] err_count_o
);
  localparam int unsigned AddressShift  = $clog2(DataWidth / 8);
  localparam int unsigned NumWordsTotal = NumBanks * NumWordsPerBank;

  // soc_mem_ss 64-bit port interface.
  logic [NumInitPorts-1:0]                   init_req;
  logic [NumInitPorts-1:0]                   init_we;
  logic [NumInitPorts-1:0][AddrWidth-1:0]    init_addr;
  logic [NumInitPorts-1:0][DataWidth-1:0]    init_wdata;
  logic [NumInitPorts-1:0][DataWidth/8-1:0]  init_be;
  logic [NumInitPorts-1:0]                   init_gnt;
  logic [NumInitPorts-1:0]                   init_rvalid;
  logic [NumInitPorts-1:0]                   init_rready;
  logic [NumInitPorts-1:0][DataWidth-1:0]    init_rdata;
  logic [NumInitPorts-1:0]                   init_err;

  // Per-port generator state.
  logic        run_q;
  logic [31:0] issued_cnt [NumInitPorts];
  logic [31:0] done_cnt   [NumInitPorts];
  logic [31:0] lfsr_q     [NumInitPorts];

  // Word index for the access a port is currently presenting.
  function automatic logic [AddrWidth-1:0] gen_addr(input int unsigned p,
                                                    input logic [31:0] issued,
                                                    input logic [31:0] lfsr,
                                                    input logic [1:0]  pat);
    logic [63:0] raw;
    logic [63:0] widx;
    begin
      unique case (pat)
        2'd0:    raw = 64'(issued) * 64'(NumBanks) + 64'(p);  // disjoint banks
        2'd1:    raw = 64'(issued) * 64'(NumBanks);           // all bank 0
        2'd2:    raw = 64'(lfsr);                              // random
        default: raw = 64'(issued);
      endcase
      widx = raw % 64'(NumWordsTotal);
      return BaseAddr + (AddrWidth'(widx) << AddressShift);
    end
  endfunction

  function automatic logic [31:0] next_lfsr(input logic [31:0] s);
    return {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction

  logic [NumInitPorts-1:0] port_done;
  logic                    all_done;

  always_comb begin
    init_req     = '0;
    init_we      = '0;
    init_addr    = '0;
    init_wdata   = '0;
    init_be      = '0;
    init_rready  = '0;
    port_done    = '0;

    for (int unsigned p = 0; p < NumInitPorts; p++) begin
      port_done[p] = !active_mask_i[p] || (done_cnt[p] >= budget_i);

      init_rready[p] = 1'b1;  // always accept responses
      // Multi-outstanding: hold the request asserted until the budget has been
      // issued and let the port's req/gnt handshake throttle how many run in
      // flight (bounded by the per-port egress reorder-buffer depth).
      init_req[p]   = run_q && active_mask_i[p] && (issued_cnt[p] < budget_i);
      init_we[p]    = we_i;
      init_addr[p]  = gen_addr(p, issued_cnt[p], lfsr_q[p], pattern_i);
      init_wdata[p] = {(DataWidth/32){issued_cnt[p]}};
      init_be[p]    = '1;
    end

    all_done = (port_done == '1);
  end

  // Aggregate counters. These must account for several ports completing in the
  // same cycle, so accesses is the sum of the per-port done counts (not a +1
  // accumulator), and the per-cycle error count is summed across ports.
  logic [31:0] err_this_cycle;
  always_comb begin
    accesses_o     = '0;
    err_this_cycle = '0;
    for (int unsigned p = 0; p < NumInitPorts; p++) begin
      accesses_o += 64'(done_cnt[p]);
      if (init_rvalid[p] && init_err[p]) begin
        err_this_cycle += 1;
      end
    end
  end

  assign running_o = run_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      run_q       <= 1'b0;
      done_o      <= 1'b0;
      timeout_o   <= 1'b0;
      cycles_o    <= '0;
      err_count_o <= '0;
      for (int unsigned p = 0; p < NumInitPorts; p++) begin
        issued_cnt[p] <= '0;
        done_cnt[p]   <= '0;
        lfsr_q[p]     <= 32'h1 + p[31:0];
      end
    end else if (start_i && !run_q) begin
      run_q       <= 1'b1;
      done_o      <= 1'b0;
      timeout_o   <= 1'b0;
      cycles_o    <= '0;
      err_count_o <= '0;
      for (int unsigned p = 0; p < NumInitPorts; p++) begin
        issued_cnt[p] <= '0;
        done_cnt[p]   <= '0;
        lfsr_q[p]     <= 32'h1 + p[31:0];
      end
    end else if (run_q) begin
      cycles_o    <= cycles_o + 1;
      err_count_o <= err_count_o + err_this_cycle;
      for (int unsigned p = 0; p < NumInitPorts; p++) begin
        if (init_req[p] && init_gnt[p]) begin
          issued_cnt[p] <= issued_cnt[p] + 1;
          lfsr_q[p]     <= next_lfsr(lfsr_q[p]);
        end
        if (init_rvalid[p] && init_rready[p]) begin
          done_cnt[p] <= done_cnt[p] + 1;
        end
      end
      if (all_done) begin
        run_q  <= 1'b0;
        done_o <= 1'b1;
      end else if (cycles_o >= MaxCycles) begin
        run_q     <= 1'b0;
        done_o    <= 1'b1;
        timeout_o <= 1'b1;
      end
    end
  end

  soc_mem_ss #(
    .NumPorts32(0),
    .NumPorts64(NumInitPorts),
    .NumBanks(NumBanks),
    .MemDataWidth(DataWidth),
    .AddrWidth(AddrWidth),
    .WordsPerBank(NumWordsPerBank),
    .BaseAddr(BaseAddr),
    .MemImpl(mem_ss_pkg::MemImplModel)
  ) i_mem_ss (
    .clk_i,
    .rst_ni,
    // 32-bit port group unused in this benchmark.
    .req32_i('0), .gnt32_o(), .we32_i('0), .addr32_i('0), .wdata32_i('0),
    .be32_i('0), .rvalid32_o(), .rready32_i('0), .rdata32_o(), .err32_o(),
    // 64-bit port group: the benchmark's init ports.
    .req64_i(init_req), .gnt64_o(init_gnt), .we64_i(init_we),
    .addr64_i(init_addr), .wdata64_i(init_wdata), .be64_i(init_be),
    .rvalid64_o(init_rvalid), .rready64_i(init_rready),
    .rdata64_o(init_rdata), .err64_o(init_err)
  );
endmodule
