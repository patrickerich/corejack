#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [timeout_seconds]" 1>&2
  exit 1
fi

ELF="$1"
TIMEOUT="${2:-5}"
ENTRY_SYMBOL="${COREJACK_GDB_ENTRY_SYMBOL:-_entry_point}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
REPO_GDB="$REPO_ROOT/.tools/riscv/bin/riscv64-unknown-elf-gdb"
RISCV64_GDB="${RISCV:-}/bin/riscv64-unknown-elf-gdb"
RISCV32_GDB="${RISCV:-}/bin/riscv32-unknown-elf-gdb"
RISCV_NONE_GDB="${RISCV:-}/bin/riscv-none-elf-gdb"

if [ -n "${GDB:-}" ]; then
  GDB_CMD="$GDB"
elif [ -x "$REPO_GDB" ]; then
  GDB_CMD="$REPO_GDB"
elif [ -n "${RISCV:-}" ] && [ -x "$RISCV64_GDB" ]; then
  GDB_CMD="$RISCV64_GDB"
elif [ -n "${RISCV:-}" ] && [ -x "$RISCV32_GDB" ]; then
  GDB_CMD="$RISCV32_GDB"
elif [ -n "${RISCV:-}" ] && [ -x "$RISCV_NONE_GDB" ]; then
  GDB_CMD="$RISCV_NONE_GDB"
elif command -v riscv64-unknown-elf-gdb >/dev/null 2>&1; then
  GDB_CMD="riscv64-unknown-elf-gdb"
elif command -v riscv32-unknown-elf-gdb >/dev/null 2>&1; then
  GDB_CMD="riscv32-unknown-elf-gdb"
else
  echo "Error: no RISC-V GDB found. Source ./sourceme.sh or set GDB=/path/to/gdb." 1>&2
  exit 1
fi

TMPFILE=$(mktemp /tmp/corejack_gdb.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << EOF
target extended-remote localhost:3333
EOF

if [ "${COREJACK_GDB_RUN_MODE:-default}" = "ndmreset-sysbus" ]; then
  "$GDB_CMD" "$ELF" \
    -batch \
    -ex "target extended-remote localhost:3333" \
    -ex "monitor riscv set_mem_access sysbus" \
    -ex "monitor riscv dmi_write 0x10 0x00000003" \
    -ex "load" \
    -ex "monitor riscv dmi_write 0x10 0x00000001" \
    -ex "detach"
  exit 0
fi

cat >> "$TMPFILE" << EOF
monitor reset halt
load
set \$pc = (unsigned long)&${ENTRY_SYMBOL}
continue
EOF

timeout --foreground --signal=INT "${TIMEOUT}" "$GDB_CMD" "$ELF" -batch -x "$TMPFILE" || {
  exit_code=$?
  if [ "$exit_code" -eq 124 ]; then
    echo "Timeout reached after ${TIMEOUT}s"
    exit 0
  fi
  exit "$exit_code"
}
