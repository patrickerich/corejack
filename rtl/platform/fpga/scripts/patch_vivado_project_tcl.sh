#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <vivado-project.tcl>" >&2
  exit 2
fi

project_tcl="$1"
marker="# CoreJack Vivado synthesis options"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../../.." && pwd)"
ibex_clock_gate_override="${repo_root}/rtl/cores/overrides/ibex/prim_clock_gating.sv"

if [ ! -f "${project_tcl}" ]; then
  echo "Error: Vivado project Tcl not found: ${project_tcl}" >&2
  exit 1
fi

if [ ! -f "${ibex_clock_gate_override}" ]; then
  echo "Error: Ibex clock-gate override not found: ${ibex_clock_gate_override}" >&2
  exit 1
fi

tmp="${project_tcl}.tmp"
awk -v ibex_clock_gate_override="${ibex_clock_gate_override}" '
  /^read_verilog[[:space:]]+-sv[[:space:]]+\{src\/corejack_ibex_design_1\.0\/rtl\/prim_clock_gating\.sv\}/ {
    print "read_verilog -sv {" ibex_clock_gate_override "}"
    next
  }
  {
    print
  }
' "${project_tcl}" > "${tmp}"
mv "${tmp}" "${project_tcl}"

if grep -qF "${marker}" "${project_tcl}"; then
  exit 0
fi

tmp="${project_tcl}.tmp"
awk -v marker="${marker}" '
  {
    print
    if (!done && $0 ~ /^create_project[[:space:]]/) {
      print ""
      print marker
      print "if {[llength [get_runs synth_1]] != 0} {"
      print "  set_property STEPS.SYNTH_DESIGN.ARGS.GATED_CLOCK_CONVERSION on [get_runs synth_1]"
      print "}"
      done = 1
    }
  }
' "${project_tcl}" > "${tmp}"
mv "${tmp}" "${project_tcl}"
