module corejack_axku5_wrap #(
  parameter int unsigned CoreType = platform_pkg::CORE_IBEX,
  parameter bit EnableUartLoader = 1'b0,
  // Shared SRAM size in 32-bit words, derived from the single source of truth
  // (cfg/boards/axku5.yaml: memory.ram_bytes / 4) and driven in by the FPGA
  // build via the corejack.core RamWords vlogparam. The default matches the
  // soc_top default (262144 words = 1 MiB), which is also the AXKU5 size, so
  // standalone elaboration and the build agree.
  parameter int unsigned RamWords = 262144
) (
  input  logic       sys_clk_p,
  input  logic       sys_clk_n,
  input  logic       sys_rst_n,
  output logic [3:0] led,
  output logic       uart_tx,
  input  logic       uart_rx,
  input  logic       jtag_tck,
  input  logic       jtag_tms,
  input  logic       jtag_trst_n,
  input  logic       jtag_tdi,
  output logic       jtag_tdo
);
  import dm::*;
  import soc_bus_pkg::*;

  logic clk_in_200;
  logic clk_in_200_buf;
  logic core_clk_raw;
  logic core_clk;
  logic pll_clkfb;
  logic pll_locked;
  logic pll_locked_r;
  logic rst_ni_raw;
  logic dmactive;
  logic debug_req;
  logic alert_minor;
  logic alert_major_internal;
  logic alert_major_bus;
  logic core_sleep;
  soc_apb_req_t apb_req_unused;
  soc_apb_resp_t apb_rsp_unused;

  IBUFDS i_sys_clk_ibufds (
    .I (sys_clk_p),
    .IB(sys_clk_n),
    .O (clk_in_200)
  );

  BUFG i_sys_clk_bufg (
    .I(clk_in_200),
    .O(clk_in_200_buf)
  );

  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(5),   // 200 MHz * 5 = 1000 MHz VCO
    .CLKIN1_PERIOD(5.0), // 200 MHz input
    .CLKOUT0_DIVIDE(40), // 1000 MHz / 40 = 25 MHz
    .DIVCLK_DIVIDE(1),
    .STARTUP_WAIT("FALSE")
  ) i_pll (
    .CLKOUT0(core_clk_raw),
    .CLKOUT1(),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKFBOUT(pll_clkfb),
    .LOCKED(pll_locked),
    .CLKIN1(clk_in_200_buf),
    .PWRDWN(1'b0),
    .RST(1'b0),
    .CLKFBIN(pll_clkfb)
  );

  BUFG i_core_clk_bufg (
    .I(core_clk_raw),
    .O(core_clk)
  );

  always_ff @(posedge core_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      pll_locked_r <= 1'b0;
      rst_ni_raw   <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni_raw   <= pll_locked_r;
    end
  end

  assign apb_req_unused = '0;

  soc_top #(
    .apb_req_t       (soc_apb_req_t),
    .apb_rsp_t       (soc_apb_resp_t),
    .axi_req_t       (soc_axi_req_t),
    .axi_rsp_t       (soc_axi_resp_t),
    .obi_req_t       (soc_obi_req_t),
    .obi_rsp_t       (soc_obi_rsp_t),
    .CoreType        (CoreType),
    .EnablePlatform  (1'b1),
    .EnableUartLoader(EnableUartLoader),
    .RamWords        (RamWords),
    .MemImpl         (mem_ss_pkg::MemImplXilinx)
  ) i_soc_top (
    .clk_i                  (core_clk),
    .rst_ni                 (rst_ni_raw),
    .apb_req_i              (apb_req_unused),
    .apb_rsp_o              (apb_rsp_unused),
    .uart_rx_i              (uart_rx),
    .uart_tx_o              (uart_tx),
    .jtag_tck_i             (jtag_tck),
    .jtag_tms_i             (jtag_tms),
    .jtag_trst_ni           (jtag_trst_n),
    .jtag_tdi_i             (jtag_tdi),
    .jtag_tdo_o             (jtag_tdo),
    .dmactive_o             (dmactive),
    .debug_req_o            (debug_req),
    .alert_minor_o          (alert_minor),
    .alert_major_internal_o (alert_major_internal),
    .alert_major_bus_o      (alert_major_bus),
    .core_sleep_o           (core_sleep)
  );

  // Stable board status:
  // led[0]: SoC reset released,
  // led[1]: debug module active,
  // led[2]: live debug request,
  // led[3]: core sleep state.
  assign led = {core_sleep, debug_req, dmactive, rst_ni_raw};
endmodule
