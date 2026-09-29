#!/usr/bin/env bash
# Single source of truth for the tracked files that define an FPGA bitstream's
# design inputs. Prints one sha256 over the sorted file set.
#
# Used by bin/write_bitstream_manifest.sh (to record DESIGN_INPUT_HASH) and by
# bin/fpga_debug_acceptance.sh (to reject a stale bitstream). Both call this
# rather than carrying their own copy of the list, so the recorded hash and the
# checked hash cannot drift apart.
#
# The rule: hash exactly the files that can change the bitstream. The set is
# default-include - a new file under cfg/, patches/, or rtl/ is hashed
# automatically - and the exclusions below are files that cannot change the
# bitstream, so editing them must not make every existing bitstream stale:
#   cfg/validation/                 smoke-test expectations (uart_banners.yaml)
#   cfg/vivado_*_allowlist.txt      review lists for the post-build Vivado gates
#   cfg/verilator_lint_waivers.vlt  simulation lint waivers
#   rtl/platform/fpga/scripts/      the OpenOCD configs, the GDB load/run
#                                   scripts, and the post-route report script;
#                                   patch_vivado_project_tcl.sh does shape the
#                                   build and stays hashed
# sw/zephyr is not hashed: nothing in the FPGA flow reads it. Every *.core file
# is, since the board and core cores carry the XDC, wrapper, and file lists. Of
# the make fragments under mk/, only deps.mk (dependency pins, the CVA6 fetch
# and patches) and fpga.mk (the FPGA build) feed the bitstream; the rest - sim,
# lint, sw, zephyr, docs, tools, project - are left out.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

excluded='^cfg/validation/|^cfg/vivado_[a-z]+_allowlist\.txt$|^cfg/verilator_lint_waivers\.vlt$|^rtl/platform/fpga/scripts/(openocd-.*\.cfg|load_elf\.sh|run_elf\.sh|report_vivado_impl\.tcl)$'

{
  git ls-files \
    'Bender.lock' \
    'Bender.yml' \
    'Makefile' \
    'mk/deps.mk' \
    'mk/fpga.mk' \
    'cfg' \
    'patches' \
    'rtl' \
    '*.core' \
    2>/dev/null || true
} | { grep -v -E "$excluded" || true; } | sort -u | xargs -r sha256sum | sha256sum | awk '{print $1}'
