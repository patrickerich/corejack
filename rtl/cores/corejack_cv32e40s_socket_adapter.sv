// SPDX-License-Identifier: Apache-2.0
//
module corejack_cv32e40s_socket_adapter #(
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
  output logic        debug_unavailable_o,
  output logic        core_sleep_o
);
  logic [31:0] irq;
  logic [1:0]  instr_memtype_unused;
  logic [2:0]  instr_prot_unused;
  logic        instr_dbg_unused;
  logic        instr_reqpar_unused;
  logic [12:0] instr_achk_unused;
  logic [1:0]  data_memtype_unused;
  logic [2:0]  data_prot_unused;
  logic        data_dbg_unused;
  logic        data_reqpar_unused;
  logic [12:0] data_achk_unused;
  logic [63:0] mcycle_unused;
  logic        fencei_flush_req_unused;
  logic        alert_major;
  logic        debug_havereset_unused;
  logic        debug_running_unused;
  logic        debug_halted_unused;
  logic        debug_pc_valid_unused;
  logic [31:0] debug_pc_unused;
  logic        unused_irq_nm;
  logic [31:0] raw_instr_addr;
  localparam logic [31:0] DmRegionStart = (DmBaseAddr == 32'h0) ? 32'h0000_0001 : DmBaseAddr;
  localparam logic [31:0] DmRegionEnd = DmBaseAddr + 32'h0000_0fff;
  localparam cv32e40s_pkg::lfsr_cfg_t Lfsr0Cfg = '{
    coeffs:       32'h8020_0003,
    default_seed: 32'hace1_1234
  };
  localparam cv32e40s_pkg::lfsr_cfg_t Lfsr1Cfg = '{
    coeffs:       32'h8020_0003,
    default_seed: 32'h1f2e_3d4c
  };
  localparam cv32e40s_pkg::lfsr_cfg_t Lfsr2Cfg = '{
    coeffs:       32'h8020_0003,
    default_seed: 32'h55aa_33cc
  };

  always_comb begin
    irq        = '0;
    irq[3]     = irq_software_i;
    irq[7]     = irq_timer_i;
    irq[11]    = irq_external_i;
    irq[30:16] = irq_fast_i;
  end

  assign alert_major_internal_o = alert_major;
  assign alert_major_bus_o      = 1'b0;
  assign unused_irq_nm          = irq_nm_i;

  cv32e40s_core #(
    .RV32             (cv32e40s_pkg::RV32I),
    .B_EXT            (cv32e40s_pkg::B_NONE),
    .M_EXT            (cv32e40s_pkg::M),
    .DEBUG            (1'b1),
    .DM_REGION_START  (DmRegionStart),
    .DM_REGION_END    (DmRegionEnd),
    .DBG_NUM_TRIGGERS (1),
    .PMA_NUM_REGIONS  (0),
    .CLIC             (1'b0),
    .PMP_NUM_REGIONS  (0),
    .LFSR0_CFG        (Lfsr0Cfg),
    .LFSR1_CFG        (Lfsr1Cfg),
    .LFSR2_CFG        (Lfsr2Cfg)
  ) i_cv32e40s (
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
    .instr_reqpar_o       (instr_reqpar_unused),
    .instr_gntpar_i       (~instr_gnt_i),
    .instr_rvalidpar_i    (~instr_rvalid_i),
    .instr_achk_o         (instr_achk_unused),
    .instr_rchk_i         ('0),
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
    .data_rdata_i         (data_rdata_i),
    .data_err_i           (data_err_i),
    .data_reqpar_o        (data_reqpar_unused),
    .data_gntpar_i        (~data_gnt_i),
    .data_rvalidpar_i     (~data_rvalid_i),
    .data_achk_o          (data_achk_unused),
    .data_rchk_i          ('0),
    .mcycle_o             (mcycle_unused),
    .irq_i                (irq),
    .wu_wfe_i             (1'b0),
    .clic_irq_i           (1'b0),
    .clic_irq_id_i        ('0),
    .clic_irq_level_i     ('0),
    .clic_irq_priv_i      ('0),
    .clic_irq_shv_i       (1'b0),
    .fencei_flush_req_o   (fencei_flush_req_unused),
    .fencei_flush_ack_i   (1'b1),
    .alert_minor_o        (alert_minor_o),
    .alert_major_o        (alert_major),
    .debug_req_i          (debug_req_i),
    .debug_havereset_o    (debug_havereset_unused),
    .debug_running_o      (debug_running_unused),
    .debug_halted_o       (debug_halted_unused),
    .debug_pc_valid_o     (debug_pc_valid_unused),
    .debug_pc_o           (debug_pc_unused),
    .fetch_enable_i       (1'b1),
    .core_sleep_o         (core_sleep_o)
  );

  assign debug_unavailable_o = 1'b0;
  assign instr_addr_o = raw_instr_addr;
endmodule
