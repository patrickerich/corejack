module soc_mem_ss
  import mem_ss_pkg::*;
#(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned NumInitPorts = 3,
  parameter int unsigned InitTagWidth = 1,
  parameter int unsigned NumBanks = 8,
  parameter int unsigned NumWordsPerBank = 16384,
  parameter logic [AddrWidth-1:0] BaseAddr = '0,
  parameter int unsigned AddressShift = $clog2(DataWidth / 8),
  parameter string MemInitPath = "",
  parameter mem_impl_e MemImpl = MemImplModel
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic [NumInitPorts-1:0]                   init_req_i,
  input  logic [NumInitPorts-1:0]                   init_we_i,
  input  logic [NumInitPorts-1:0][AddrWidth-1:0]    init_addr_i,
  input  logic [NumInitPorts-1:0][DataWidth-1:0]    init_wdata_i,
  input  logic [NumInitPorts-1:0][DataWidth/8-1:0]  init_be_i,
  input  logic [NumInitPorts-1:0][InitTagWidth-1:0] init_tag_i,

  output logic [NumInitPorts-1:0]                   init_gnt_o,
  output logic [NumInitPorts-1:0]                   init_rvalid_o,
  input  logic [NumInitPorts-1:0]                   init_rready_i,
  output logic [NumInitPorts-1:0][DataWidth-1:0]    init_rdata_o,
  output logic [NumInitPorts-1:0]                   init_err_o,
  output logic [NumInitPorts-1:0][InitTagWidth-1:0] init_rtag_o
);
  // Arbitration contract:
  // - Per-bank round-robin arbitration is used to avoid starvation.
  // - Upstream initiators must hold requests asserted until grant. Small
  //   ingress buffers can be added later, but fairness already depends on
  //   request persistence rather than one-cycle request pulses.
  localparam int unsigned BankSelWidth = (NumBanks > 1) ? $clog2(NumBanks) : 1;
  localparam int unsigned PortSelWidth = (NumInitPorts > 1) ? $clog2(NumInitPorts) : 1;
  localparam bit ExtraRspLatency = (MemImpl == MemImplXilinx);
  // Total addressable words across all banks. Init-port accesses outside
  // [BaseAddr, BaseAddr + NumWordsTotal words) are rejected (see addr_in_range)
  // so a misroute errors cleanly instead of aliasing into RAM.
  localparam int unsigned NumWordsTotal = NumBanks * NumWordsPerBank;

  logic [NumBanks-1:0]                  bank_req;
  logic [NumBanks-1:0]                  bank_we;
  logic [NumBanks-1:0][AddrWidth-1:0]   bank_addr;
  logic [NumBanks-1:0][DataWidth-1:0]   bank_wdata;
  logic [NumBanks-1:0][DataWidth/8-1:0] bank_be;
  logic [NumBanks-1:0][DataWidth-1:0]   bank_rdata;
  logic [NumBanks-1:0]                  bank_rsp_valid_q;
  logic [NumBanks-1:0]                  bank_rsp_err_q;
  logic [NumBanks-1:0][PortSelWidth-1:0] bank_rsp_port_q;
  logic [NumBanks-1:0][InitTagWidth-1:0] bank_rsp_tag_q;
  logic [NumBanks-1:0]                  bank_pending_valid_q;
  logic [NumBanks-1:0][PortSelWidth-1:0] bank_pending_port_q;
  logic [NumBanks-1:0][InitTagWidth-1:0] bank_pending_tag_q;
  logic [NumBanks-1:0]                  bank_rsp_ready;
  logic [NumBanks-1:0]                  bank_accept_ready;
  logic [NumBanks-1:0]                  bank_grant_valid;
  logic [NumBanks-1:0][PortSelWidth-1:0] bank_grant_port;
  logic [NumBanks-1:0][PortSelWidth-1:0] bank_rr_start_q;
  logic [NumBanks-1:0][PortSelWidth-1:0] bank_rr_start_d;
  // Per-port error responses for out-of-range init accesses. Each init port is
  // single-outstanding, so one error slot per port is sufficient.
  logic [NumInitPorts-1:0]                    err_rsp_valid_q;
  logic [NumInitPorts-1:0][InitTagWidth-1:0]  err_rsp_tag_q;
  logic [NumInitPorts-1:0]                    err_grant;
  logic [NumInitPorts-1:0]                    err_rsp_ready;

  function automatic logic [BankSelWidth-1:0] calc_bank_sel(
    input logic [AddrWidth-1:0] addr
  );
    logic [AddrWidth-1:0] word_addr;
    begin
      word_addr = (addr - BaseAddr) >> AddressShift;
      return word_addr[BankSelWidth-1:0];
    end
  endfunction

  function automatic logic [AddrWidth-1:0] calc_bank_addr(
    input logic [AddrWidth-1:0] addr
  );
    logic [AddrWidth-1:0] local_word_addr;
    logic [AddrWidth-1:0] bank_word_addr;
    begin
      local_word_addr = (addr - BaseAddr) >> AddressShift;
      bank_word_addr = local_word_addr >> BankSelWidth;
      return bank_word_addr << AddressShift;
    end
  endfunction

  // Returns 1 when addr lies within the addressable RAM range
  // [BaseAddr, BaseAddr + NumWordsTotal words). Out-of-range init accesses are
  // turned into clean error responses instead of aliasing into a bank.
  function automatic logic addr_in_range(input logic [AddrWidth-1:0] addr);
    logic [AddrWidth-1:0] word_addr;
    begin
      if (addr < BaseAddr) begin
        return 1'b0;
      end
      word_addr = (addr - BaseAddr) >> AddressShift;
      return word_addr < AddrWidth'(NumWordsTotal);
    end
  endfunction

  always_comb begin
    init_gnt_o    = '0;
    init_rvalid_o = '0;
    init_rdata_o  = '0;
    init_err_o    = '0;
    init_rtag_o   = '0;
    bank_req      = '0;
    bank_we       = '0;
    bank_addr     = '0;
    bank_wdata    = '0;
    bank_be       = '0;
    bank_rsp_ready = '0;
    bank_accept_ready = '0;
    bank_grant_valid = '0;
    bank_grant_port  = '0;
    bank_rr_start_d  = bank_rr_start_q;
    err_grant        = '0;
    err_rsp_ready    = '0;

    for (int unsigned bank = 0; bank < NumBanks; bank++) begin
      bank_rsp_ready[bank] = !bank_rsp_valid_q[bank] ||
                             init_rready_i[bank_rsp_port_q[bank]];
      bank_accept_ready[bank] = bank_rsp_ready[bank] &&
                                (!ExtraRspLatency || !bank_pending_valid_q[bank]);
      for (int unsigned offset = 0; offset < NumInitPorts; offset++) begin
        int unsigned port;
        port = bank_rr_start_q[bank] + offset;
        if (port >= NumInitPorts) begin
          port -= NumInitPorts;
        end
        if (bank_accept_ready[bank] && !bank_grant_valid[bank] && init_req_i[port] &&
            addr_in_range(init_addr_i[port]) &&
            (calc_bank_sel(init_addr_i[port]) == bank)) begin
          bank_grant_valid[bank] = 1'b1;
          bank_grant_port[bank]  = port[PortSelWidth-1:0];
          bank_req[bank]         = 1'b1;
          bank_we[bank]          = init_we_i[port];
          bank_addr[bank]        = calc_bank_addr(init_addr_i[port]);
          bank_wdata[bank]       = init_wdata_i[port];
          bank_be[bank]          = init_be_i[port];
          init_gnt_o[port]       = 1'b1;
          if (port == NumInitPorts - 1) begin
            bank_rr_start_d[bank] = '0;
          end else begin
            bank_rr_start_d[bank] = PortSelWidth'(port + 1);
          end
        end
      end
    end

    // Out-of-range init accesses never reach a bank: grant them immediately and
    // schedule a one-cycle error response so a misroute fails cleanly.
    for (int unsigned port = 0; port < NumInitPorts; port++) begin
      err_rsp_ready[port] = !err_rsp_valid_q[port] || init_rready_i[port];
      if (err_rsp_ready[port] && init_req_i[port] &&
          !addr_in_range(init_addr_i[port])) begin
        err_grant[port]  = 1'b1;
        init_gnt_o[port] = 1'b1;
      end
    end

    for (int unsigned port = 0; port < NumInitPorts; port++) begin
      for (int unsigned bank = 0; bank < NumBanks; bank++) begin
        if (bank_rsp_valid_q[bank] && (bank_rsp_port_q[bank] == port)) begin
          init_rvalid_o[port] = 1'b1;
          init_rdata_o[port]  = bank_rdata[bank];
          init_err_o[port]    = bank_rsp_err_q[bank];
          init_rtag_o[port]   = bank_rsp_tag_q[bank];
        end
      end
      if (err_rsp_valid_q[port]) begin
        init_rvalid_o[port] = 1'b1;
        init_rdata_o[port]  = '0;
        init_err_o[port]    = 1'b1;
        init_rtag_o[port]   = err_rsp_tag_q[port];
      end
    end
  end

  for (genvar bank = 0; bank < NumBanks; bank++) begin : gen_banks
    soc_sram_slice_wrapper #(
      .NumWords(NumWordsPerBank),
      .DataWidth(DataWidth),
      .AddressShift(AddressShift),
      .MemImpl(MemImpl)
    ) u_bank (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .req_i(bank_req[bank]),
      .we_i(bank_we[bank]),
      .addr_i(bank_addr[bank][31:0]),
      .wdata_i(bank_wdata[bank]),
      .be_i(bank_be[bank]),
      .rdata_o(bank_rdata[bank])
    );

`ifndef SYNTHESIS
    initial begin : init_bank_from_file
      string mem_path;
      string file_path;

      if (MemInitPath != "") begin
        mem_path = MemInitPath;
      end else if ($value$plusargs("MEM_PATH=%s", mem_path)) begin
      end else begin
        mem_path = "";
      end

      if (mem_path != "") begin
        if (mem_path[mem_path.len()-1] != "/") begin
          mem_path = {mem_path, "/"};
        end
        file_path = $sformatf("%sbank_%0d.hex", mem_path, bank);
        $display("soc_mem_ss: loading bank %0d from %s", bank, file_path);
        u_bank.load_mem(file_path);
      end
    end
`endif
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bank_rsp_valid_q <= '0;
      bank_rsp_err_q   <= '0;
      bank_rsp_port_q  <= '0;
      bank_rsp_tag_q   <= '0;
      bank_pending_valid_q <= '0;
      bank_pending_port_q  <= '0;
      bank_pending_tag_q   <= '0;
      bank_rr_start_q  <= '0;
      err_rsp_valid_q  <= '0;
      err_rsp_tag_q    <= '0;
    end else begin
      bank_rr_start_q  <= bank_rr_start_d;
      for (int unsigned bank = 0; bank < NumBanks; bank++) begin
        if (bank_rsp_ready[bank]) begin
          if (ExtraRspLatency) begin
            bank_rsp_valid_q[bank] <= bank_pending_valid_q[bank];
          end else begin
            bank_rsp_valid_q[bank] <= bank_grant_valid[bank];
          end
          bank_rsp_err_q[bank]   <= 1'b0;
          bank_rsp_port_q[bank]  <= '0;
          bank_rsp_tag_q[bank]   <= '0;
        end
        if (bank_rsp_ready[bank] && ExtraRspLatency) begin
          bank_pending_valid_q[bank] <= bank_grant_valid[bank];
          bank_pending_port_q[bank]  <= '0;
          bank_pending_tag_q[bank]   <= '0;
          if (bank_pending_valid_q[bank]) begin
            bank_rsp_port_q[bank] <= bank_pending_port_q[bank];
            bank_rsp_tag_q[bank]  <= bank_pending_tag_q[bank];
          end
          if (bank_grant_valid[bank]) begin
            bank_pending_port_q[bank] <= bank_grant_port[bank];
            bank_pending_tag_q[bank]  <= init_tag_i[bank_grant_port[bank]];
          end
        end else if (bank_rsp_ready[bank] && bank_grant_valid[bank]) begin
          bank_rsp_port_q[bank] <= bank_grant_port[bank];
          bank_rsp_tag_q[bank]  <= init_tag_i[bank_grant_port[bank]];
        end
      end
      for (int unsigned port = 0; port < NumInitPorts; port++) begin
        if (err_rsp_ready[port]) begin
          err_rsp_valid_q[port] <= err_grant[port];
          if (err_grant[port]) begin
            err_rsp_tag_q[port] <= init_tag_i[port];
          end
        end
      end
    end
  end
endmodule
