# Digilent Arty A7-100T constraints for the CoreJack FPGA wrapper.
# Pin assignments follow the Digilent Arty-A7-100 master XDC. The external
# JTAG signals are routed to Pmod JD; see docs/source/jtag_wiring.md.

# Artix-7 bitstream configuration bank voltage (required to clear config DRCs).
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# 100 MHz single-ended system clock (CLK100MHZ).
create_clock -period 10.000 -name sys_clk_pin [get_ports sys_clk]
set_property PACKAGE_PIN E3 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

# Active-low reset button (ck_rst).
set_property PACKAGE_PIN C2 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]
set_property PULLTYPE PULLUP [get_ports sys_rst_n]
set_switching_activity -static_probability 1.0 -toggle_rate 0.0 [get_ports sys_rst_n]
# The reset input is board-static outside explicit button presses. Vivado's
# vectorless power analysis may still infer excessive reset assertion on
# high-fanout synchronized reset nets; this activity constraint records the
# board-level intent for power analysis.

# Core reset is asserted asynchronously and released through rstgen. Avoid
# same-edge recovery/removal checks from that synchronizer output into
# downstream async reset pins.
set_false_path \
  -from [get_pins -hierarchical -quiet -filter {NAME =~ *i_rstgen_core/i_rstgen_bypass/synch_regs_q_reg[3]/C}] \
  -through [get_pins -hierarchical -quiet {*/CLR}]
set_false_path \
  -from [get_pins -hierarchical -quiet -filter {NAME =~ *i_rstgen_core/i_rstgen_bypass/synch_regs_q_reg[3]/C}] \
  -through [get_pins -hierarchical -quiet {*/PRE}]

# User LEDs (LD4-LD7).
set_property PACKAGE_PIN H5 [get_ports {led[0]}]
set_property PACKAGE_PIN J5 [get_ports {led[1]}]
set_property PACKAGE_PIN T9 [get_ports {led[2]}]
set_property PACKAGE_PIN T10 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

# USB-UART bridge. uart_rxd_out is the FPGA TX; uart_txd_in is the FPGA RX.
set_property PACKAGE_PIN D10 [get_ports uart_tx]
set_property PACKAGE_PIN A9 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

# External JTAG on Pmod JD (Arty uses Olimex ARM-USB-TINY; see docs/source/jtag_wiring.md):
#   JD1=D4 -> jtag_tck   JD2=D3 -> jtag_tms
#   JD3=F4 -> jtag_tdo   JD4=F3 -> jtag_tdi   JD7=E2 -> jtag_trst_n
# Connect the probe GND to a Pmod JD GND pin (5/11) and the probe reference
# voltage to 3V3 (6/12).
set_property PACKAGE_PIN D4 [get_ports jtag_tck]
set_property PACKAGE_PIN D3 [get_ports jtag_tms]
set_property PACKAGE_PIN F4 [get_ports jtag_tdo]
set_property PACKAGE_PIN F3 [get_ports jtag_tdi]
set_property PACKAGE_PIN E2 [get_ports jtag_trst_n]
set_property IOSTANDARD LVCMOS33 [get_ports {jtag_tck jtag_tms jtag_trst_n jtag_tdi jtag_tdo}]
set_property PULLTYPE PULLUP [get_ports {jtag_tms jtag_trst_n}]

create_clock -period 100.000 -name jtag_tck_pin [get_ports jtag_tck]
set_clock_groups -asynchronous \
  -group [get_clocks jtag_tck_pin] \
  -group [get_clocks -include_generated_clocks sys_clk_pin]

set_max_delay -to   [get_ports {jtag_tdo}] 20
set_max_delay -from [get_ports {jtag_tms}] 20
set_max_delay -from [get_ports {jtag_tdi}] 20
set_max_delay -from [get_ports {jtag_trst_n}] 20
set_false_path -from [get_ports {jtag_trst_n}]

set_property CLOCK_BUFFER_TYPE NONE [get_ports jtag_tck]
