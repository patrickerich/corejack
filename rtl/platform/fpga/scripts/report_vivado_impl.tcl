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

report_utilization \
  -hierarchical \
  -file [file join $report_dir utilization_hier.rpt]

puts "INFO: Vivado implementation reports written to $report_dir"
close_project
