#!/usr/bin/env bash
# Single source of truth for the tracked files that define an FPGA bitstream's
# design inputs. Prints one sha256 over the sorted file set.
#
# Used by bin/write_bitstream_manifest.sh (to record DESIGN_INPUT_HASH) and by
# bin/fpga_debug_acceptance.sh (to reject a stale bitstream). Both call this
# rather than carrying their own copy of the list, so the recorded hash and the
# checked hash cannot drift apart.
#
# The set is default-include: adding a new cfg/ subdirectory is hashed
# automatically. cfg/validation/ is the one deliberate carve-out -- it holds
# smoke-test expectations (uart_banners.yaml) that cannot affect generated
# hardware, so editing them must not invalidate every existing bitstream.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

{
  git ls-files \
    'Bender.lock' \
    'Bender.yml' \
    'Makefile' \
    'cfg' \
    'patches' \
    'rtl' \
    'corejack.core' \
    'sw/zephyr/boards' \
    'sw/zephyr/soc' \
    2>/dev/null || true
} | { grep -v '^cfg/validation/' || true; } | sort | xargs -r sha256sum | sha256sum | awk '{print $1}'
