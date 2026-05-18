module corejack_picorv32_socket_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0080
) (
  input  logic        clk_i,
  input  logic        rst_ni,

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
  logic        mem_valid;
  logic        mem_instr;
  logic        mem_ready;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [3:0]  mem_wstrb;
  logic [31:0] mem_rdata;

  logic        trace_valid_unused;
  logic [35:0] trace_data_unused;
  logic        trap_unused;

  logic        mem_is_write;
  logic        mem_is_instr;
  logic        mem_is_data;
  logic        mem_accept;
  logic        outstanding_q;
  logic        outstanding_instr_q;
  logic        outstanding_write_q;

  assign mem_is_write = |mem_wstrb;
  assign mem_is_instr = mem_valid && mem_instr && !mem_is_write;
  assign mem_is_data  = mem_valid && (!mem_instr || mem_is_write);

  assign instr_req_o  = mem_is_instr && !outstanding_q;
  assign instr_addr_o = mem_addr;

  assign data_req_o   = mem_is_data && !outstanding_q;
  assign data_we_o    = mem_is_write;
  assign data_be_o    = mem_wstrb;
  assign data_addr_o  = mem_addr;
  assign data_wdata_o = mem_wdata;

  assign mem_accept = (instr_req_o && instr_gnt_i) || (data_req_o && data_gnt_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      outstanding_q       <= 1'b0;
      outstanding_instr_q <= 1'b0;
      outstanding_write_q <= 1'b0;
    end else begin
      if (mem_accept) begin
        outstanding_q       <= 1'b1;
        outstanding_instr_q <= instr_req_o;
        outstanding_write_q <= data_req_o && data_we_o;
      end

      if (mem_ready) begin
        outstanding_q       <= 1'b0;
        outstanding_instr_q <= 1'b0;
        outstanding_write_q <= 1'b0;
      end
    end
  end

  assign mem_ready =
      (outstanding_instr_q && instr_rvalid_i)
   || (!outstanding_instr_q && outstanding_q && data_rvalid_i);

  assign mem_rdata =
      outstanding_instr_q ? instr_rdata_i :
      outstanding_write_q ? 32'h0 :
                            data_rdata_i;

  assign core_sleep_o = 1'b0;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (instr_err_i && instr_rvalid_i) begin
        $fatal(1, "PicoRV32 instruction bus error is not supported");
      end

      if (data_err_i && data_rvalid_i) begin
        $fatal(1, "PicoRV32 data bus error is not supported");
      end
    end
  end
`endif

  picorv32 #(
    .ENABLE_COUNTERS      (0),
    .ENABLE_COUNTERS64    (0),
    .ENABLE_REGS_16_31    (1),
    .ENABLE_REGS_DUALPORT (1),
    .TWO_STAGE_SHIFT      (1),
    .BARREL_SHIFTER       (0),
    .TWO_CYCLE_COMPARE    (0),
    .TWO_CYCLE_ALU        (0),
    .COMPRESSED_ISA       (1),
    .ENABLE_MUL           (1),
    .ENABLE_FAST_MUL      (0),
    .ENABLE_DIV           (1),
    .ENABLE_IRQ           (0),
    .ENABLE_IRQ_QREGS     (0),
    .ENABLE_IRQ_TIMER     (0),
    .ENABLE_TRACE         (0),
    .REGS_INIT_ZERO       (0),
    .MASKED_IRQ           (32'hffff_ffff),
    .LATCHED_IRQ          (32'h0000_0000),
    .PROGADDR_RESET       (BootAddr),
    .PROGADDR_IRQ         (32'h0000_0000),
    .STACKADDR            (32'h800f_fff0)
  ) i_picorv32 (
    .clk         (clk_i),
    .resetn      (rst_ni),
    .trap        (trap_unused),
    .mem_valid   (mem_valid),
    .mem_instr   (mem_instr),
    .mem_ready   (mem_ready),
    .mem_addr    (mem_addr),
    .mem_wdata   (mem_wdata),
    .mem_wstrb   (mem_wstrb),
    .mem_rdata   (mem_rdata),
    .mem_la_read (),
    .mem_la_write(),
    .mem_la_addr (),
    .mem_la_wdata(),
    .mem_la_wstrb(),
    .pcpi_valid  (),
    .pcpi_insn   (),
    .pcpi_rs1    (),
    .pcpi_rs2    (),
    .pcpi_wr     (1'b0),
    .pcpi_rd     (32'h0),
    .pcpi_wait   (1'b0),
    .pcpi_ready  (1'b0),
    .irq         (32'h0),
    .eoi         (),
    .trace_valid (trace_valid_unused),
    .trace_data  (trace_data_unused)
  );
endmodule
