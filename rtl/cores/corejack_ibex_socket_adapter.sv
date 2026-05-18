module corejack_ibex_socket_adapter #(
  parameter logic [31:0] BootAddr = 32'h8000_0000,
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
  import ibex_pkg::*;

  prim_ram_1p_pkg::ram_1p_cfg_t ram_cfg_icache_tag;
  prim_ram_1p_pkg::ram_1p_cfg_t ram_cfg_icache_data;
  prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_rsp_icache_tag;
  prim_ram_1p_pkg::ram_1p_cfg_rsp_t [ibex_pkg::IC_NUM_WAYS-1:0] ram_cfg_rsp_icache_data;
  logic [6:0] instr_rdata_intg;
  logic [6:0] data_wdata_intg;
  logic [6:0] data_rdata_intg;
  logic       scramble_req;
  crash_dump_t crash_dump_unused;
  ibex_mubi_t lockstep_cmp_en_unused;
  logic       double_fault_seen_unused;
  logic       data_req_shadow_unused;
  logic       data_we_shadow_unused;
  logic [3:0] data_be_shadow_unused;
  logic [31:0] data_addr_shadow_unused;
  logic [31:0] data_wdata_shadow_unused;
  logic [6:0] data_wdata_intg_shadow_unused;
  logic       instr_req_shadow_unused;
  logic [31:0] instr_addr_shadow_unused;

  assign ram_cfg_icache_tag  = '0;
  assign ram_cfg_icache_data = '0;
  assign instr_rdata_intg    = '0;
  assign data_rdata_intg     = '0;

  corejack_ibex_wrapper #(
    .RegFile(ibex_pkg::RegFileFPGA),
    .RV32M(ibex_pkg::RV32MFast),
    .RV32B(ibex_pkg::RV32BBalanced),
    .BranchTargetALU(1'b1),
    .WritebackStage(1'b1),
    .ICache(1'b0),
    .ICacheECC(1'b0),
    .ICacheTweakInfection(1'b0),
    .BranchPredictor(1'b0),
    .DbgTriggerEn(1'b0),
    .SecureIbex(1'b0),
    .PMPEnable(1'b0),
    .DmBaseAddr(DmBaseAddr),
    .DmHaltAddr(DmHaltAddr),
    .DmExceptionAddr(DmExceptionAddr)
  ) i_ibex (
    .clk_i                    (clk_i),
    .rst_ni                   (rst_ni),
    .test_en_i                (1'b0),
    .ram_cfg_icache_tag_i     (ram_cfg_icache_tag),
    .ram_cfg_rsp_icache_tag_o (ram_cfg_rsp_icache_tag),
    .ram_cfg_icache_data_i    (ram_cfg_icache_data),
    .ram_cfg_rsp_icache_data_o(ram_cfg_rsp_icache_data),
    .hart_id_i                (HartId),
    .boot_addr_i              (BootAddr),
    .instr_req_o              (instr_req_o),
    .instr_gnt_i              (instr_gnt_i),
    .instr_rvalid_i           (instr_rvalid_i),
    .instr_addr_o             (instr_addr_o),
    .instr_rdata_i            (instr_rdata_i),
    .instr_rdata_intg_i       (instr_rdata_intg),
    .instr_err_i              (instr_err_i),
    .data_req_o               (data_req_o),
    .data_gnt_i               (data_gnt_i),
    .data_rvalid_i            (data_rvalid_i),
    .data_we_o                (data_we_o),
    .data_be_o                (data_be_o),
    .data_addr_o              (data_addr_o),
    .data_wdata_o             (data_wdata_o),
    .data_wdata_intg_o        (data_wdata_intg),
    .data_rdata_i             (data_rdata_i),
    .data_rdata_intg_i        (data_rdata_intg),
    .data_err_i               (data_err_i),
    .irq_software_i           (irq_software_i),
    .irq_timer_i              (irq_timer_i),
    .irq_external_i           (irq_external_i),
    .irq_fast_i               (irq_fast_i),
    .irq_nm_i                 (irq_nm_i),
    .scramble_key_valid_i     (1'b0),
    .scramble_key_i           ('0),
    .scramble_nonce_i         ('0),
    .scramble_req_o           (scramble_req),
    .debug_req_i              (debug_req_i),
    .crash_dump_o             (crash_dump_unused),
    .double_fault_seen_o      (double_fault_seen_unused),
    .fetch_enable_i           (ibex_pkg::IbexMuBiOn),
    .alert_minor_o            (alert_minor_o),
    .alert_major_internal_o   (alert_major_internal_o),
    .alert_major_bus_o        (alert_major_bus_o),
    .core_sleep_o             (core_sleep_o),
    .lockstep_cmp_en_o        (lockstep_cmp_en_unused),
    .data_req_shadow_o        (data_req_shadow_unused),
    .data_we_shadow_o         (data_we_shadow_unused),
    .data_be_shadow_o         (data_be_shadow_unused),
    .data_addr_shadow_o       (data_addr_shadow_unused),
    .data_wdata_shadow_o      (data_wdata_shadow_unused),
    .data_wdata_intg_shadow_o (data_wdata_intg_shadow_unused),
    .instr_req_shadow_o       (instr_req_shadow_unused),
    .instr_addr_shadow_o      (instr_addr_shadow_unused),
    .scan_rst_ni              (rst_ni)
  );
endmodule
