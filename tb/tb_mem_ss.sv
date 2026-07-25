// SPDX-License-Identifier: Apache-2.0
//
// Self-checking testbench for the redesigned memory subsystem (soc_mem_ss).
//
// Verifies the hard guarantees directly:
//   - never-drop + correctness: every request gets exactly one response, and
//     read data matches a reference model;
//   - in-order: each port has a FIFO scoreboard, so an out-of-order response
//     fails immediately;
//   - backpressure: rready is randomly stalled on every port;
//   - errors: out-of-range addresses must return err=1 (and never touch memory);
//   - no-starvation/concurrency: all ports drive continuously; if any port were
//     starved its scoreboard would never drain and the run would time out.
//
// Each port owns a disjoint 64-bit-word region so there are no cross-port RAW
// hazards and the reference model is exact. Built standalone with Verilator
// (--binary --timing) plus the common_cells and slice-model dependencies.
module tb_mem_ss;
  localparam int unsigned NumPorts32   = 2;
  localparam int unsigned NumPorts64   = 2;
  localparam int unsigned NumBanks     = 4;
  localparam int unsigned WordsPerBank = 64;
  localparam int unsigned EgressDepth  = 2;
  localparam logic [31:0] BaseAddr     = 32'h8000_0000;
  localparam int unsigned TotalWords64 = NumBanks * WordsPerBank;      // 256
  localparam int unsigned TotalBytes   = TotalWords64 * 8;
  localparam int unsigned AccPerPort   = 4000;

  logic clk, rst_n;

  // Port wiring.
  logic [NumPorts32-1:0]        req32, gnt32, we32, rvalid32, rready32, err32;
  logic [NumPorts32-1:0][31:0]  addr32, wdata32, rdata32;
  logic [NumPorts32-1:0][3:0]   be32;
  logic [NumPorts64-1:0]        req64, gnt64, we64, rvalid64, rready64, err64;
  logic [NumPorts64-1:0][31:0]  addr64;
  logic [NumPorts64-1:0][63:0]  wdata64, rdata64;
  logic [NumPorts64-1:0][7:0]   be64;

  soc_mem_ss #(
    .NumPorts32(NumPorts32), .NumPorts64(NumPorts64), .NumBanks(NumBanks),
    .WordsPerBank(WordsPerBank), .BaseAddr(BaseAddr), .EgressDepth(EgressDepth),
`ifdef MEMIMPL_XILINX
    .MemImpl(mem_ss_pkg::MemImplXilinx)
`else
    .MemImpl(mem_ss_pkg::MemImplModel)
`endif
  ) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .req32_i(req32), .gnt32_o(gnt32), .we32_i(we32), .addr32_i(addr32),
    .wdata32_i(wdata32), .be32_i(be32), .rvalid32_o(rvalid32),
    .rready32_i(rready32), .rdata32_o(rdata32), .err32_o(err32),
    .req64_i(req64), .gnt64_o(gnt64), .we64_i(we64), .addr64_i(addr64),
    .wdata64_i(wdata64), .be64_i(be64), .rvalid64_o(rvalid64),
    .rready64_i(rready64), .rdata64_o(rdata64), .err64_o(err64)
  );

  // Clock / reset.
  initial clk = 0;
  always #5 clk = ~clk;

  // Reference model and per-port scoreboards.
  // 64-bit-word reference, indexed by global 64-bit word.
  logic [63:0] ref_mem [TotalWords64];

  typedef struct {
    bit         is_read;
    bit         err;
    logic [63:0] data;   // expected read data (low 32 bits used for 32-bit ports)
  } exp_t;

  exp_t sb32 [NumPorts32][$];
  exp_t sb64 [NumPorts64][$];
  int   done32 [NumPorts32];
  int   done64 [NumPorts64];
  int   errors;

  // Region assignment (disjoint 64-bit words):
  //   32-bit port g -> 64-bit words [g*RW32, (g+1)*RW32)
  //   64-bit port g -> 64-bit words [Base64 + g*RW64, ...)
  localparam int unsigned RW32   = 16;                       // 64-bit words per 32-bit port
  localparam int unsigned Base64 = NumPorts32 * RW32;        // first 64-bit-port word
  localparam int unsigned RW64   = 16;

  function automatic int unsigned rnd_range(int unsigned lo, int unsigned hi);
    return lo + ($urandom % (hi - lo));
  endfunction

  // ---- 32-bit port driver/monitor ----
  for (genvar g = 0; g < NumPorts32; g++) begin : gen_d32
    // Driver.
    initial begin
      int unsigned w64, w32, widx;
      logic [31:0] data;
      bit oor;
      req32[g] = 0; we32[g] = 0; addr32[g] = 0; wdata32[g] = 0; be32[g] = 0;
      @(posedge rst_n);
      // Phase A: write every 32-bit word in region.
      for (w32 = 0; w32 < RW32 * 2; w32++) begin
        w64  = g * RW32 + (w32 / 2);
        widx = w32 % 2;
        data = 32'hA000_0000 | (g << 24) | w32;
        @(negedge clk);
        req32[g] = 1; we32[g] = 1;
        addr32[g] = BaseAddr + (w64 * 8) + (widx * 4);
        wdata32[g] = data; be32[g] = 4'hF;
        @(posedge clk);
        while (!gnt32[g]) @(posedge clk);
        ref_mem[w64][widx*32 +: 32] = data;
        sb32[g].push_back('{is_read:0, err:0, data:0});
        @(negedge clk); req32[g] = 0;
      end
      // Phase B: random read/write, occasional out-of-range.
      repeat (AccPerPort) begin
        oor  = ($urandom % 16 == 0);
        w32  = rnd_range(0, RW32 * 2);
        w64  = g * RW32 + (w32 / 2);
        widx = w32 % 2;
        @(negedge clk);
        req32[g] = 1;
        if (oor) begin
          we32[g]   = ($urandom & 1);
          addr32[g] = BaseAddr + TotalBytes + (w32 * 4);  // out of range
          wdata32[g] = $urandom; be32[g] = 4'hF;
        end else if ($urandom & 1) begin                  // write
          data = $urandom;
          we32[g] = 1; addr32[g] = BaseAddr + (w64*8) + (widx*4);
          wdata32[g] = data; be32[g] = 4'hF;
        end else begin                                    // read
          we32[g] = 0; addr32[g] = BaseAddr + (w64*8) + (widx*4);
          be32[g] = 4'hF;
        end
        @(posedge clk);
        while (!gnt32[g]) @(posedge clk);
        if (oor)
          sb32[g].push_back('{is_read:~we32[g], err:1, data:0});
        else if (we32[g]) begin
          ref_mem[w64][widx*32 +: 32] = wdata32[g];
          sb32[g].push_back('{is_read:0, err:0, data:0});
        end else
          sb32[g].push_back('{is_read:1, err:0, data:64'(ref_mem[w64][widx*32 +: 32])});
        @(negedge clk); req32[g] = 0;
      end
    end
    // Monitor.
    initial begin
      exp_t e;
      rready32[g] = 0;
      @(posedge rst_n);
      forever begin
        @(negedge clk);
        rready32[g] = ($urandom % 4 != 0);  // random backpressure
        @(posedge clk);
        if (rvalid32[g] && rready32[g]) begin
          if (sb32[g].size() == 0) begin
            $error("port32[%0d]: unexpected response", g); errors++;
          end else begin
            e = sb32[g].pop_front();
            if (err32[g] !== e.err) begin
              $error("port32[%0d]: err %b exp %b", g, err32[g], e.err); errors++;
            end else if (e.is_read && !e.err && (rdata32[g] !== e.data[31:0])) begin
              $error("port32[%0d]: rdata %08x exp %08x", g, rdata32[g], e.data[31:0]); errors++;
            end
            done32[g]++;
          end
        end
      end
    end
  end

  // ---- 64-bit port driver/monitor ----
  for (genvar g = 0; g < NumPorts64; g++) begin : gen_d64
    initial begin
      int unsigned w64;
      logic [63:0] data;
      bit oor;
      req64[g] = 0; we64[g] = 0; addr64[g] = 0; wdata64[g] = 0; be64[g] = 0;
      @(posedge rst_n);
      for (w64 = 0; w64 < RW64; w64++) begin
        data = {32'hB000_0000 | (g << 24) | w64, 32'hC000_0000 | w64};
        @(negedge clk);
        req64[g] = 1; we64[g] = 1; addr64[g] = BaseAddr + ((Base64 + g*RW64 + w64) * 8);
        wdata64[g] = data; be64[g] = 8'hFF;
        @(posedge clk);
        while (!gnt64[g]) @(posedge clk);
        ref_mem[Base64 + g*RW64 + w64] = data;
        sb64[g].push_back('{is_read:0, err:0, data:0});
        @(negedge clk); req64[g] = 0;
      end
      repeat (AccPerPort) begin
        oor = ($urandom % 16 == 0);
        w64 = rnd_range(0, RW64);
        @(negedge clk);
        req64[g] = 1;
        if (oor) begin
          we64[g] = ($urandom & 1); addr64[g] = BaseAddr + TotalBytes + (w64*8);
          wdata64[g] = {$urandom, $urandom}; be64[g] = 8'hFF;
        end else if ($urandom & 1) begin
          data = {$urandom, $urandom};
          we64[g] = 1; addr64[g] = BaseAddr + ((Base64 + g*RW64 + w64)*8);
          wdata64[g] = data; be64[g] = 8'hFF;
        end else begin
          we64[g] = 0; addr64[g] = BaseAddr + ((Base64 + g*RW64 + w64)*8); be64[g] = 8'hFF;
        end
        @(posedge clk);
        while (!gnt64[g]) @(posedge clk);
        if (oor)
          sb64[g].push_back('{is_read:~we64[g], err:1, data:0});
        else if (we64[g]) begin
          ref_mem[Base64 + g*RW64 + w64] = wdata64[g];
          sb64[g].push_back('{is_read:0, err:0, data:0});
        end else
          sb64[g].push_back('{is_read:1, err:0, data:ref_mem[Base64 + g*RW64 + w64]});
        @(negedge clk); req64[g] = 0;
      end
    end
    initial begin
      exp_t e;
      rready64[g] = 0;
      @(posedge rst_n);
      forever begin
        @(negedge clk);
        rready64[g] = ($urandom % 4 != 0);
        @(posedge clk);
        if (rvalid64[g] && rready64[g]) begin
          if (sb64[g].size() == 0) begin
            $error("port64[%0d]: unexpected response", g); errors++;
          end else begin
            e = sb64[g].pop_front();
            if (err64[g] !== e.err) begin
              $error("port64[%0d]: err %b exp %b", g, err64[g], e.err); errors++;
            end else if (e.is_read && !e.err && (rdata64[g] !== e.data)) begin
              $error("port64[%0d]: rdata %016x exp %016x", g, rdata64[g], e.data); errors++;
            end
            done64[g]++;
          end
        end
      end
    end
  end

  // Reset + completion watchdog.
  initial begin
    int total_exp, i;
    errors = 0;
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    total_exp = (NumPorts32 * (RW32*2 + AccPerPort)) + (NumPorts64 * (RW64 + AccPerPort));

    // Wait until every scoreboard has drained (all responses received).
    fork : watch
      begin
        forever begin
          int outstanding;
          @(posedge clk);
          outstanding = 0;
          for (i = 0; i < NumPorts32; i++) outstanding += sb32[i].size();
          for (i = 0; i < NumPorts64; i++) outstanding += sb64[i].size();
          if (outstanding == 0) begin
            // give drivers a few cycles to confirm fully drained
            repeat (20) @(posedge clk);
            outstanding = 0;
            for (i = 0; i < NumPorts32; i++) outstanding += sb32[i].size();
            for (i = 0; i < NumPorts64; i++) outstanding += sb64[i].size();
            if (outstanding == 0) disable watch;
          end
        end
      end
      begin
        repeat (4_000_000) @(posedge clk);
        $error("TIMEOUT: scoreboards never drained (possible drop or starvation)");
        errors++;
        disable watch;
      end
    join

    // Empty scoreboards are necessary but not sufficient: entries are pushed
    // at grant time, so a port that stops being *granted* drains to empty
    // while its access budget is unspent. Require the completed-access count
    // to match the budget so grant starvation cannot produce a false PASS.
    begin
      int total_done;
      total_done = 0;
      for (i = 0; i < NumPorts32; i++) total_done += done32[i];
      for (i = 0; i < NumPorts64; i++) total_done += done64[i];
      if (total_done != total_exp) begin
        $error("completed %0d of %0d budgeted accesses (grant starvation?)",
               total_done, total_exp);
        errors++;
      end
    end

    if (errors == 0) $display("TB_MEM_SS: PASS (all %0d accesses checked)", total_exp);
    else             $display("TB_MEM_SS: FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
