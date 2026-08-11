if {$argc < 1} {
  puts "ERROR: Usage: report_vivado_impl.tcl <project.xpr> \[report_dir\]"
  exit 1
}

set xpr_file [file normalize [lindex $argv 0]]
if {$argc >= 2} {
  set report_dir [file normalize [lindex $argv 1]]
} else {
  set report_dir [file join [file dirname $xpr_file] reports]
}

if {![file exists $xpr_file]} {
  puts "ERROR: Vivado project not found: $xpr_file"
  exit 1
}

file mkdir $report_dir
open_project $xpr_file

if {[catch {open_run impl_1} err]} {
  puts "ERROR: Could not open impl_1: $err"
  close_project
  exit 1
}

# The XDC already groups the JTAG TCK and generated core clock domains as
# asynchronous. report_clock_interaction records that explicitly, so avoid
# promoting Vivado's generic multi-clock reminder to a warning.
set_msg_config -id {Timing 38-164} -new_severity INFO

report_route_status \
  -file [file join $report_dir route_status.rpt]

report_timing_summary \
  -delay_type max \
  -report_unconstrained \
  -check_timing_verbose \
  -max_paths 20 \
  -file [file join $report_dir timing_summary.rpt]

report_timing \
  -delay_type max \
  -sort_by group \
  -from [get_clocks core_clk_raw] \
  -to [get_clocks core_clk_raw] \
  -max_paths 20 \
  -nworst 5 \
  -file [file join $report_dir timing_core_worst_paths.rpt]

report_timing \
  -delay_type max \
  -sort_by group \
  -from [get_clocks jtag_tck_pin] \
  -to [get_clocks jtag_tck_pin] \
  -max_paths 20 \
  -nworst 5 \
  -file [file join $report_dir timing_jtag_worst_paths.rpt]

report_clock_interaction \
  -file [file join $report_dir clock_interaction.rpt]

# Key timing numbers in a greppable form.
#
# CORE_CLK_WNS_NS is the intra-clock worst slack on core_clk_raw - the SoC
# clock - and is the number that reflects this design's logic. DESIGN_WNS_NS is
# report_timing_summary's whole-design minimum across every path group; in these
# builds that is normally a single JTAG/IO endpoint, so it is a poor proxy for
# SoC timing and is recorded separately and labelled rather than led with.
#
# Slack sign convention: positive means the constraint is met with that much
# margin, negative means it is violated by that amount.
#
# Note when cross-checking against timing_summary.rpt by hand: core_clk_raw
# paths are split across that report's Intra Clock Table and its
# **async_default** row in Other Path Groups. get_timing_paths spans both, so
# CORE_CLK_WNS_NS can be lower than the Intra Clock Table figure alone - it is
# the worst of every core_clk_raw -> core_clk_raw path, which is what matters.
set core_clk [get_clocks -quiet core_clk_raw]
set core_wns ""
set core_period ""
if {[llength $core_clk] > 0} {
  set core_period [get_property -quiet PERIOD [lindex $core_clk 0]]
  set core_paths [get_timing_paths -quiet -from $core_clk -to $core_clk \
                                   -delay_type max -max_paths 1]
  if {[llength $core_paths] > 0} {
    set core_wns [get_property SLACK [lindex $core_paths 0]]
  }
}

set design_wns ""
set design_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $design_paths] > 0} {
  set design_wns [get_property SLACK [lindex $design_paths 0]]
}

set timing_key [open [file join $report_dir timing_key.txt] w]
puts $timing_key "# CoreJack key timing numbers. Positive slack = constraint met."
puts $timing_key "# CORE_CLK_WNS_NS is the SoC clock and is the meaningful number."
puts $timing_key "# DESIGN_WNS_NS spans all path groups and is often a lone JTAG/IO"
puts $timing_key "# endpoint; do not read it as SoC logic timing."
puts $timing_key "CORE_CLK_PERIOD_NS=$core_period"
puts $timing_key "CORE_CLK_WNS_NS=$core_wns"
puts $timing_key "DESIGN_WNS_NS=$design_wns"
if {$design_wns ne "" && $design_wns >= 0} {
  puts $timing_key "DESIGN_TIMING_MET=1"
} else {
  puts $timing_key "DESIGN_TIMING_MET=0"
}
close $timing_key

puts "INFO: core_clk_raw WNS = $core_wns ns (design-wide WNS = $design_wns ns)"

report_utilization \
  -hierarchical \
  -file [file join $report_dir utilization_hier.rpt]

puts "INFO: Vivado implementation reports written to $report_dir"
close_project
