// SPDX-License-Identifier: Apache-2.0
//
module soc_dut;
  import platform_pkg::*;
  import soc_bus_pkg::*;

`ifdef COREJACK_CORE_CV32E40P
  localparam int unsigned SocCoreType = CoreCv32e40p;
`elsif COREJACK_CORE_CV32E40X
  localparam int unsigned SocCoreType = CoreCv32e40x;
`elsif COREJACK_CORE_CV32E40S
  localparam int unsigned SocCoreType = CoreCv32e40s;
`elsif COREJACK_CORE_CVA6
  localparam int unsigned SocCoreType = CoreCva6;
`elsif COREJACK_CORE_SERV
  localparam int unsigned SocCoreType = CoreServ;
`elsif COREJACK_CORE_PICORV32
  localparam int unsigned SocCoreType = CorePicorv32;
`elsif COREJACK_CORE_CVW
  localparam int unsigned SocCoreType = CoreCvw;
`else
  localparam int unsigned SocCoreType = CoreIbex;
`endif

`ifdef COREJACK_SIM_XILINX_SRAM
  localparam mem_ss_pkg::mem_impl_e SocMemImpl = mem_ss_pkg::MemImplXilinx;
`else
  localparam mem_ss_pkg::mem_impl_e SocMemImpl = mem_ss_pkg::MemImplModel;
`endif

  logic clk_i;
  logic rst_ni;
  logic sim_print_valid;
  logic [7:0] sim_print_data;
  logic sim_status_valid;
  logic sim_status_pass;
  logic [31:0] sim_status_code;
  logic obi_sim_status_valid;
  logic obi_sim_status_pass;
  logic [31:0] obi_sim_status_code;
  logic axi_sim_status_valid;
  logic axi_sim_status_pass;
  logic [31:0] axi_sim_status_code;
`ifdef DEBUG_TEST_HOOKS
  logic dbg_force_core_req;
  logic dbg_force_sba_req;
  logic dbg_force_debug_req;
  logic dbg_force_ndmreset;
  logic dbg_instr_req;
  logic [31:0] dbg_instr_addr;
  logic dbg_data_req;
  logic dbg_data_we;
  logic [3:0] dbg_data_be;
  logic [31:0] dbg_data_addr;
  logic [31:0] dbg_data_wdata;
  logic dbg_sba_req;
  logic dbg_sba_we;
  logic [3:0] dbg_sba_be;
  logic [31:0] dbg_sba_addr;
  logic [31:0] dbg_sba_wdata;
  logic dbg_cva6_debug_mode;
  logic dbg_cva6_set_debug_pc;
  logic dbg_cva6_halt_frontend;
  logic dbg_cva6_frontend_req;
  logic dbg_cva6_frontend_ready;
  logic dbg_cva6_frontend_valid;
  logic dbg_cva6_axi_aw_valid;
  logic dbg_cva6_axi_aw_ready;
  logic dbg_cva6_axi_w_valid;
  logic dbg_cva6_axi_w_ready;
  logic dbg_cva6_axi_ar_valid;
  logic dbg_cva6_axi_ar_ready;
  logic [63:0] dbg_cva6_frontend_npc;
  logic [63:0] dbg_cva6_frontend_vaddr;
  logic [63:0] dbg_cva6_frontend_data;
  logic [47:0] dbg_cva6_axi_aw_addr;
  logic [47:0] dbg_cva6_axi_ar_addr;
`endif

  soc_apb_req_t apb_req;
  soc_apb_resp_t apb_rsp;

  assign apb_req = '0;

  soc_top #(
    .CoreType(SocCoreType),
    .apb_req_t(soc_apb_req_t),
    .apb_rsp_t(soc_apb_resp_t),
    .MemImpl(SocMemImpl),
    .EnablePlatform(1'b1)
  ) i_soc_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .apb_req_i(apb_req),
    .apb_rsp_o(apb_rsp),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .jtag_tck_i(1'b0),
    .jtag_tms_i(1'b0),
    .jtag_trst_ni(1'b0),
    .jtag_tdi_i(1'b0),
    .jtag_tdo_o(),
    .dmactive_o(),
    .debug_req_o(),
    .alert_minor_o(),
    .alert_major_internal_o(),
    .alert_major_bus_o(),
    .core_sleep_o()
  );

  uart_apb_tx_monitor #(
    .apb_req_t(soc_apb_req_t)
  ) i_uart_apb_tx_monitor (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .uart_apb_req_i(i_soc_top.gen_platform.uart_apb_req),
    .tx_valid_o(sim_print_valid),
    .tx_data_o(sim_print_data)
  );

  sim_ctrl_monitor i_sim_ctrl_monitor (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .data_req_i(i_soc_top.gen_platform.data_req),
    .data_we_i(i_soc_top.gen_platform.data_we),
    .data_addr_i(i_soc_top.gen_platform.data_addr),
    .data_wdata_i(i_soc_top.gen_platform.data_wdata),
    .status_valid_o(obi_sim_status_valid),
    .status_pass_o(obi_sim_status_pass),
    .status_code_o(obi_sim_status_code)
  );

  // The sim-ctrl status write targets a magic address outside every decoded
  // window, so with the crossbar it lands on the error slave rather than a
  // target port. Observe it at the initiator side instead: core_axi_req[0]
  // carries CVA6's data writes (the AXI-native case the OBI monitor above
  // cannot see); the aw/w handshake still completes against the xbar error
  // slave, so the write is captured here.
  axi_sim_ctrl_monitor i_axi_sim_ctrl_monitor (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(i_soc_top.gen_platform.core_axi_req[0]),
    .rsp_i(i_soc_top.gen_platform.core_axi_rsp[0]),
    .status_valid_o(axi_sim_status_valid),
    .status_pass_o(axi_sim_status_pass),
    .status_code_o(axi_sim_status_code)
  );

  assign sim_status_valid = obi_sim_status_valid || axi_sim_status_valid;
  assign sim_status_pass  = axi_sim_status_valid ? axi_sim_status_pass : obi_sim_status_pass;
  assign sim_status_code  = axi_sim_status_valid ? axi_sim_status_code : obi_sim_status_code;

`ifdef DEBUG_TEST_HOOKS
  always_comb begin
    if (dbg_force_core_req) begin
      force i_soc_top.gen_platform.instr_req   = dbg_instr_req;
      force i_soc_top.gen_platform.instr_addr  = dbg_instr_addr;
      force i_soc_top.gen_platform.data_req    = dbg_data_req;
      force i_soc_top.gen_platform.data_we     = dbg_data_we;
      force i_soc_top.gen_platform.data_be     = dbg_data_be;
      force i_soc_top.gen_platform.data_addr   = dbg_data_addr;
      force i_soc_top.gen_platform.data_wdata  = dbg_data_wdata;
    end else begin
      release i_soc_top.gen_platform.instr_req;
      release i_soc_top.gen_platform.instr_addr;
      release i_soc_top.gen_platform.data_req;
      release i_soc_top.gen_platform.data_we;
      release i_soc_top.gen_platform.data_be;
      release i_soc_top.gen_platform.data_addr;
      release i_soc_top.gen_platform.data_wdata;
    end

    if (dbg_force_sba_req) begin
      force i_soc_top.gen_platform.sba_req   = dbg_sba_req;
      force i_soc_top.gen_platform.sba_we    = dbg_sba_we;
      force i_soc_top.gen_platform.sba_be    = dbg_sba_be;
      force i_soc_top.gen_platform.sba_addr  = dbg_sba_addr;
      force i_soc_top.gen_platform.sba_wdata = dbg_sba_wdata;
    end else begin
      release i_soc_top.gen_platform.sba_req;
      release i_soc_top.gen_platform.sba_we;
      release i_soc_top.gen_platform.sba_be;
      release i_soc_top.gen_platform.sba_addr;
      release i_soc_top.gen_platform.sba_wdata;
    end

    if (dbg_force_ndmreset) begin
      force i_soc_top.gen_platform.ndmreset = 1'b1;
    end else begin
      release i_soc_top.gen_platform.ndmreset;
    end

    if (dbg_force_debug_req) begin
      force i_soc_top.debug_req_o = 1'b1;
    end else begin
      release i_soc_top.debug_req_o;
    end
  end

`ifdef COREJACK_CORE_CVA6
  assign dbg_cva6_debug_mode   =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.debug_mode;
  assign dbg_cva6_set_debug_pc =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.set_debug_pc;
  assign dbg_cva6_halt_frontend =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.halt_frontend;
  assign dbg_cva6_frontend_req =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.icache_dreq_o.req;
  assign dbg_cva6_frontend_ready =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.icache_dreq_i.ready;
  assign dbg_cva6_frontend_valid =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.icache_dreq_i.valid;
  assign dbg_cva6_frontend_npc =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.npc_q;
  assign dbg_cva6_frontend_vaddr =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.icache_dreq_o.vaddr;
  assign dbg_cva6_frontend_data =
      i_soc_top.gen_platform.gen_cva6_core_path.i_cva6_core.i_cva6.i_frontend.icache_dreq_i.data;
  assign dbg_cva6_axi_aw_valid = i_soc_top.gen_platform.cva6_axi_req.aw_valid;
  assign dbg_cva6_axi_aw_ready = i_soc_top.gen_platform.cva6_axi_rsp.aw_ready;
  assign dbg_cva6_axi_w_valid  = i_soc_top.gen_platform.cva6_axi_req.w_valid;
  assign dbg_cva6_axi_w_ready  = i_soc_top.gen_platform.cva6_axi_rsp.w_ready;
  assign dbg_cva6_axi_ar_valid = i_soc_top.gen_platform.cva6_axi_req.ar_valid;
  assign dbg_cva6_axi_ar_ready = i_soc_top.gen_platform.cva6_axi_rsp.ar_ready;
  assign dbg_cva6_axi_aw_addr  = i_soc_top.gen_platform.cva6_axi_req.aw.addr;
  assign dbg_cva6_axi_ar_addr  = i_soc_top.gen_platform.cva6_axi_req.ar.addr;
`else
  assign dbg_cva6_debug_mode   = 1'b0;
  assign dbg_cva6_set_debug_pc = 1'b0;
  assign dbg_cva6_halt_frontend = 1'b0;
  assign dbg_cva6_frontend_req = 1'b0;
  assign dbg_cva6_frontend_ready = 1'b0;
  assign dbg_cva6_frontend_valid = 1'b0;
  assign dbg_cva6_frontend_npc = '0;
  assign dbg_cva6_frontend_vaddr = '0;
  assign dbg_cva6_frontend_data = '0;
  assign dbg_cva6_axi_aw_valid = 1'b0;
  assign dbg_cva6_axi_aw_ready = 1'b0;
  assign dbg_cva6_axi_w_valid  = 1'b0;
  assign dbg_cva6_axi_w_ready  = 1'b0;
  assign dbg_cva6_axi_ar_valid = 1'b0;
  assign dbg_cva6_axi_ar_ready = 1'b0;
  assign dbg_cva6_axi_aw_addr  = '0;
  assign dbg_cva6_axi_ar_addr  = '0;
`endif
`endif
endmodule
