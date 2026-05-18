module corejack_cv32e40x_socket_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0000,
  parameter logic [31:0] MtvecAddr = 32'h8000_0000,
  parameter logic [31:0] HartId = 32'h0,
  parameter logic [31:0] DmBaseAddr = 32'h0000_0000,
  parameter logic [31:0] DmHaltAddr = 32'h0000_0800,
  parameter logic [31:0] DmExceptionAddr = 32'h0000_0810
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        debug_req_i,
  input  logic        irq_software_i,
  input  logic        irq_timer_i,
  input  logic        irq_external_i,
  input  logic [14:0] irq_fast_i,
  input  logic        irq_nm_i,

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

  output logic        alert_minor_o,
  output logic        alert_major_internal_o,
  output logic        alert_major_bus_o,
  output logic        core_sleep_o
);
  logic [31:0] irq;
  logic [1:0]  instr_memtype_unused;
  logic [2:0]  instr_prot_unused;
  logic        instr_dbg_unused;
  logic [1:0]  data_memtype_unused;
  logic [2:0]  data_prot_unused;
  logic        data_dbg_unused;
  logic [5:0]  data_atop_unused;
  logic [63:0] mcycle_unused;
  logic        fencei_flush_req_unused;
  logic        debug_havereset_unused;
  logic        debug_running_unused;
  logic        debug_halted_unused;
  logic        debug_pc_valid_unused;
  logic [31:0] debug_pc_unused;
  logic        unused_irq_nm;
  logic [31:0] raw_instr_addr;
  logic        raw_instr_in_dm_region;
  logic        raw_instr_after_debug_resume_q;
  logic        raw_instr_after_debug_resume_d;
  localparam logic [31:0] DmRegionStart = (DmBaseAddr == 32'h0) ? 32'h0000_0001 : DmBaseAddr;
  localparam logic [31:0] DmRegionEnd = DmBaseAddr + 32'h0000_0fff;

  cv32e40x_if_xif xif_compressed_if();
  cv32e40x_if_xif xif_issue_if();
  cv32e40x_if_xif xif_commit_if();
  cv32e40x_if_xif xif_mem_if();
  cv32e40x_if_xif xif_mem_result_if();
  cv32e40x_if_xif xif_result_if();

  always_comb begin
    irq        = '0;
    irq[3]     = irq_software_i;
    irq[7]     = irq_timer_i;
    irq[11]    = irq_external_i;
    irq[30:16] = irq_fast_i;
  end

  assign xif_compressed_if.compressed_ready = 1'b0;
  assign xif_compressed_if.compressed_resp  = '0;
  assign xif_compressed_if.issue_valid      = 1'b0;
  assign xif_compressed_if.issue_ready      = 1'b0;
  assign xif_compressed_if.issue_req        = '0;
  assign xif_compressed_if.issue_resp       = '0;
  assign xif_compressed_if.commit_valid     = 1'b0;
  assign xif_compressed_if.commit           = '0;
  assign xif_compressed_if.mem_valid        = 1'b0;
  assign xif_compressed_if.mem_ready        = 1'b0;
  assign xif_compressed_if.mem_req          = '0;
  assign xif_compressed_if.mem_resp         = '0;
  assign xif_compressed_if.mem_result_valid = 1'b0;
  assign xif_compressed_if.mem_result       = '0;
  assign xif_compressed_if.result_valid     = 1'b0;
  assign xif_compressed_if.result_ready     = 1'b0;
  assign xif_compressed_if.result           = '0;

  assign xif_issue_if.compressed_valid      = 1'b0;
  assign xif_issue_if.compressed_ready      = 1'b0;
  assign xif_issue_if.compressed_req        = '0;
  assign xif_issue_if.compressed_resp       = '0;
  assign xif_issue_if.issue_ready           = 1'b0;
  assign xif_issue_if.issue_resp            = '0;
  assign xif_issue_if.commit_valid          = 1'b0;
  assign xif_issue_if.commit                = '0;
  assign xif_issue_if.mem_valid             = 1'b0;
  assign xif_issue_if.mem_ready             = 1'b0;
  assign xif_issue_if.mem_req               = '0;
  assign xif_issue_if.mem_resp              = '0;
  assign xif_issue_if.mem_result_valid      = 1'b0;
  assign xif_issue_if.mem_result            = '0;
  assign xif_issue_if.result_valid          = 1'b0;
  assign xif_issue_if.result_ready          = 1'b0;
  assign xif_issue_if.result                = '0;

  assign xif_commit_if.compressed_valid     = 1'b0;
  assign xif_commit_if.compressed_ready     = 1'b0;
  assign xif_commit_if.compressed_req       = '0;
  assign xif_commit_if.compressed_resp      = '0;
  assign xif_commit_if.issue_valid          = 1'b0;
  assign xif_commit_if.issue_ready          = 1'b0;
  assign xif_commit_if.issue_req            = '0;
  assign xif_commit_if.issue_resp           = '0;
  assign xif_commit_if.mem_valid            = 1'b0;
  assign xif_commit_if.mem_ready            = 1'b0;
  assign xif_commit_if.mem_req              = '0;
  assign xif_commit_if.mem_resp             = '0;
  assign xif_commit_if.mem_result_valid     = 1'b0;
  assign xif_commit_if.mem_result           = '0;
  assign xif_commit_if.result_valid         = 1'b0;
  assign xif_commit_if.result_ready         = 1'b0;
  assign xif_commit_if.result               = '0;

  assign xif_mem_if.compressed_valid        = 1'b0;
  assign xif_mem_if.compressed_ready        = 1'b0;
  assign xif_mem_if.compressed_req          = '0;
  assign xif_mem_if.compressed_resp         = '0;
  assign xif_mem_if.issue_valid             = 1'b0;
  assign xif_mem_if.issue_ready             = 1'b0;
  assign xif_mem_if.issue_req               = '0;
  assign xif_mem_if.issue_resp              = '0;
  assign xif_mem_if.commit_valid            = 1'b0;
  assign xif_mem_if.commit                  = '0;
  assign xif_mem_if.mem_valid               = 1'b0;
  assign xif_mem_if.mem_req                 = '0;
  assign xif_mem_if.mem_result_valid        = 1'b0;
  assign xif_mem_if.mem_result              = '0;
  assign xif_mem_if.result_valid            = 1'b0;
  assign xif_mem_if.result_ready            = 1'b0;
  assign xif_mem_if.result                  = '0;

  assign xif_mem_result_if.compressed_valid = 1'b0;
  assign xif_mem_result_if.compressed_ready = 1'b0;
  assign xif_mem_result_if.compressed_req   = '0;
  assign xif_mem_result_if.compressed_resp  = '0;
  assign xif_mem_result_if.issue_valid      = 1'b0;
  assign xif_mem_result_if.issue_ready      = 1'b0;
  assign xif_mem_result_if.issue_req        = '0;
  assign xif_mem_result_if.issue_resp       = '0;
  assign xif_mem_result_if.commit_valid     = 1'b0;
  assign xif_mem_result_if.commit           = '0;
  assign xif_mem_result_if.mem_valid        = 1'b0;
  assign xif_mem_result_if.mem_ready        = 1'b0;
  assign xif_mem_result_if.mem_req          = '0;
  assign xif_mem_result_if.mem_resp         = '0;
  assign xif_mem_result_if.result_valid     = 1'b0;
  assign xif_mem_result_if.result_ready     = 1'b0;
  assign xif_mem_result_if.result           = '0;

  assign xif_result_if.compressed_valid     = 1'b0;
  assign xif_result_if.compressed_ready     = 1'b0;
  assign xif_result_if.compressed_req       = '0;
  assign xif_result_if.compressed_resp      = '0;
  assign xif_result_if.issue_valid          = 1'b0;
  assign xif_result_if.issue_ready          = 1'b0;
  assign xif_result_if.issue_req            = '0;
  assign xif_result_if.issue_resp           = '0;
  assign xif_result_if.commit_valid         = 1'b0;
  assign xif_result_if.commit               = '0;
  assign xif_result_if.mem_valid            = 1'b0;
  assign xif_result_if.mem_ready            = 1'b0;
  assign xif_result_if.mem_req              = '0;
  assign xif_result_if.mem_resp             = '0;
  assign xif_result_if.mem_result_valid     = 1'b0;
  assign xif_result_if.mem_result           = '0;
  assign xif_result_if.result_valid         = 1'b0;
  assign xif_result_if.result               = '0;

  assign alert_minor_o          = 1'b0;
  assign alert_major_internal_o = 1'b0;
  assign alert_major_bus_o      = 1'b0;
  assign unused_irq_nm          = irq_nm_i;

  cv32e40x_core #(
    .RV32             (cv32e40x_pkg::RV32I),
    .A_EXT            (cv32e40x_pkg::A_NONE),
    .B_EXT            (cv32e40x_pkg::B_NONE),
    .M_EXT            (cv32e40x_pkg::M),
    .DEBUG            (1'b1),
    .DM_REGION_START  (DmRegionStart),
    .DM_REGION_END    (DmRegionEnd),
    .DBG_NUM_TRIGGERS (1),
    .PMA_NUM_REGIONS  (0),
    .CLIC             (1'b0),
    .X_EXT            (1'b0),
    .NUM_MHPMCOUNTERS (1)
  ) i_cv32e40x (
    .clk_i                (clk_i),
    .rst_ni               (rst_ni),
    .scan_cg_en_i         (1'b0),
    .boot_addr_i          (BootAddr),
    .dm_exception_addr_i  (DmExceptionAddr),
    .dm_halt_addr_i       (DmHaltAddr),
    .mhartid_i            (HartId),
    .mimpid_patch_i       (4'h0),
    .mtvec_addr_i         (MtvecAddr),
    .instr_req_o          (instr_req_o),
    .instr_gnt_i          (instr_gnt_i),
    .instr_rvalid_i       (instr_rvalid_i),
    .instr_addr_o         (raw_instr_addr),
    .instr_memtype_o      (instr_memtype_unused),
    .instr_prot_o         (instr_prot_unused),
    .instr_dbg_o          (instr_dbg_unused),
    .instr_rdata_i        (instr_rdata_i),
    .instr_err_i          (instr_err_i),
    .data_req_o           (data_req_o),
    .data_gnt_i           (data_gnt_i),
    .data_rvalid_i        (data_rvalid_i),
    .data_addr_o          (data_addr_o),
    .data_be_o            (data_be_o),
    .data_we_o            (data_we_o),
    .data_wdata_o         (data_wdata_o),
    .data_memtype_o       (data_memtype_unused),
    .data_prot_o          (data_prot_unused),
    .data_dbg_o           (data_dbg_unused),
    .data_atop_o          (data_atop_unused),
    .data_rdata_i         (data_rdata_i),
    .data_err_i           (data_err_i),
    .data_exokay_i        (1'b0),
    .mcycle_o             (mcycle_unused),
    .time_i               (64'h0),
    .xif_compressed_if    (xif_compressed_if.cpu_compressed),
    .xif_issue_if         (xif_issue_if.cpu_issue),
    .xif_commit_if        (xif_commit_if.cpu_commit),
    .xif_mem_if           (xif_mem_if.cpu_mem),
    .xif_mem_result_if    (xif_mem_result_if.cpu_mem_result),
    .xif_result_if        (xif_result_if.cpu_result),
    .irq_i                (irq),
    .wu_wfe_i             (1'b0),
    .clic_irq_i           (1'b0),
    .clic_irq_id_i        ('0),
    .clic_irq_level_i     ('0),
    .clic_irq_priv_i      ('0),
    .clic_irq_shv_i       (1'b0),
    .fencei_flush_req_o   (fencei_flush_req_unused),
    .fencei_flush_ack_i   (1'b1),
    .debug_req_i          (debug_req_i),
    .debug_havereset_o    (debug_havereset_unused),
    .debug_running_o      (debug_running_unused),
    .debug_halted_o       (debug_halted_unused),
    .debug_pc_valid_o     (debug_pc_valid_unused),
    .debug_pc_o           (debug_pc_unused),
    .fetch_enable_i       (1'b1),
    .core_sleep_o         (core_sleep_o)
  );

  assign raw_instr_in_dm_region = ((raw_instr_addr - DmBaseAddr) < 32'h0000_1000);

  always_comb begin
    raw_instr_after_debug_resume_d = raw_instr_after_debug_resume_q;

    if (debug_halted_unused) begin
      raw_instr_after_debug_resume_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      raw_instr_after_debug_resume_q <= 1'b0;
    end else begin
      raw_instr_after_debug_resume_q <= raw_instr_after_debug_resume_d;
    end
  end

  // CV32E40X updates its prefetch address register on a boot/branch redirect
  // even when no instruction transaction is issued in that cycle. The first
  // visible OBI request is therefore the incremented word address. Debug entry
  // and debug-resumed execution do not show that offset, so keep those fetches
  // at their raw address.
  assign instr_addr_o =
      (raw_instr_in_dm_region || raw_instr_after_debug_resume_q) ? raw_instr_addr : raw_instr_addr - 32'd4;
endmodule
