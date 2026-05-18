#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 path/to/program.elf [additional GDB -ex commands...]" 1>&2
  exit 1
fi

ELF="$1"
shift

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

exec "$GDB_CMD" "$ELF" \
  -ex "target extended-remote localhost:3333" \
  -ex "monitor reset halt" \
  -ex "load" \
  -ex "set \$pc = (unsigned int)&_entry_point" \
  -ex "continue" \
  "$@"
