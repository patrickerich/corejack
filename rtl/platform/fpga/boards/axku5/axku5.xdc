# AXKU5 constraints for the CoreJack Ibex FPGA wrapper.

create_clock -period 5.000 -name sys_clk_pin [get_ports sys_clk_p]
set_property PACKAGE_PIN K22 [get_ports sys_clk_p]
set_property PACKAGE_PIN K23 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]

set_property PACKAGE_PIN J14 [get_ports sys_rst_n]
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

set_property PACKAGE_PIN J12 [get_ports {led[0]}]
set_property PACKAGE_PIN H14 [get_ports {led[1]}]
set_property PACKAGE_PIN F13 [get_ports {led[2]}]
set_property PACKAGE_PIN H12 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

set_property PACKAGE_PIN AD15 [get_ports uart_tx]
set_property PACKAGE_PIN AE15 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

set_property PACKAGE_PIN A13 [get_ports jtag_tck]
set_property PACKAGE_PIN G12 [get_ports jtag_tms]
set_property PACKAGE_PIN E13 [get_ports jtag_tdi]
set_property PACKAGE_PIN D14 [get_ports jtag_tdo]
set_property PACKAGE_PIN C12 [get_ports jtag_trst_n]
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
