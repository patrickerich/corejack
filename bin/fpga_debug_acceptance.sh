#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bin/fpga_debug_acceptance.sh [options]

Run the FPGA acceptance flow for one or more supported cores.

Debug-capable cores use OpenOCD/GDB. FPGA-supported cores without debug support
use the UART SRAM loader.

Options:
  --board <name>       Board descriptor to test (default: axku5)
  --cores <list>       Space- or comma-separated core list
                       (default: board compatible_cores from descriptor)
  --firmware <name>    Firmware stack to test: baremetal or zephyr
                       (default: baremetal)
  --app <name>         Software app to build and run (default: hello_world)
  --zephyr-app <name>  Zephyr app build label (default: corejack_hello)
  --gdb-timeout <sec>  Timeout used by make fpga-run-sw (default: 10)
  --uart <device>      Optional UART device to capture during debug runs;
                       required for UART-loader cores
  --uart-timeout <sec> UART capture timeout (default: 15)
  --skip-sim           Skip sim-run-sw
  --skip-bit           Skip fpga-bit. Programming still requires a matching
                       bitstream manifest from an earlier fpga-bit run.
  --skip-pgm           Skip fpga-pgm
  --skip-run           Skip fpga-run-sw
  --skip-step          Skip the direct GDB step smoke for debug-capable cores
  --keep-openocd       Leave OpenOCD running after the last tested core
  -h, --help           Show this help

Run from the repository root after sourcing ./sourceme.sh.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

board="axku5"
cores=""
firmware="baremetal"
app="hello_world"
zephyr_app="corejack_hello"
gdb_timeout="10"
uart_dev="${UART_DEV:-}"
uart_timeout="${UART_CAPTURE_TIMEOUT:-15}"
skip_sim=0
skip_bit=0
skip_pgm=0
skip_run=0
skip_step=0
keep_openocd=0

while [ $# -gt 0 ]; do
  case "$1" in
    --board)
      board="${2:?missing value for --board}"
      shift 2
      ;;
    --cores)
      if [ $# -lt 2 ]; then
        echo "Error: missing value for --cores" >&2
        exit 1
      fi
      cores="$2"
      shift 2
      ;;
    --app)
      app="${2:?missing value for --app}"
      shift 2
      ;;
    --firmware)
      firmware="${2:?missing value for --firmware}"
      shift 2
      ;;
    --zephyr-app)
      zephyr_app="${2:?missing value for --zephyr-app}"
      shift 2
      ;;
    --gdb-timeout)
      gdb_timeout="${2:?missing value for --gdb-timeout}"
      shift 2
      ;;
    --uart)
      uart_dev="${2:-}"
      shift 2
      ;;
    --uart-timeout)
      uart_timeout="${2:?missing value for --uart-timeout}"
      shift 2
      ;;
    --skip-sim)
      skip_sim=1
      shift
      ;;
    --skip-bit)
      skip_bit=1
      shift
      ;;
    --skip-pgm)
      skip_pgm=1
      shift
      ;;
    --skip-run)
      skip_run=1
      shift
      ;;
    --skip-step)
      skip_step=1
      shift
      ;;
    --keep-openocd)
      keep_openocd=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
esac
done

cores="${cores//,/ }"
case "$firmware" in
  baremetal|zephyr)
    ;;
  *)
    echo "Error: unsupported firmware stack: $firmware" >&2
    echo "Available firmware stacks: baremetal, zephyr" >&2
    exit 2
    ;;
esac

log_dir="$repo_root/logs/fpga_acceptance"
mkdir -p "$log_dir"

if [ -z "$cores" ]; then
  compatible_cores="$("${PYTHON:-python3.13}" bin/validate_target.py --board "$board" --compatible-cores)"
  cores=""
  for core in $compatible_cores; do
    if "${PYTHON:-python3.13}" bin/validate_target.py --core "$core" --board "$board" --flow fpga --quiet >/dev/null 2>&1; then
      cores="${cores:+$cores }$core"
    fi
  done
fi
if [ -z "$cores" ]; then
  echo "Error: no supported FPGA cores found for BOARD=$board" >&2
  exit 1
fi

openocd_pid=""
openocd_log=""
uart_pid=""
uart_log=""
summary_cores=()
summary_firmware=()
summary_work_roots=()
summary_bitstreams=()
summary_uart_logs=()
summary_results=()

target_config_value() {
  local core="$1"
  local key="$2"

  make target-config CORE="$core" BOARD="$board" | sed -n "s/^${key}=//p" | tail -n 1
}

uart_banner_lines() {
  local core="$1"
  local variant="$2"
  shift 2

  "${PYTHON:-python3.13}" bin/validate_target.py \
    --core "$core" \
    --board "$board" \
    --uart-banner \
    --firmware "$firmware" \
    --variant "$variant" \
    "$@"
}

fpga_work_root() {
  local core="$1"

  if [ -n "${FPGA_WORK_ROOT:-}" ]; then
    printf '%s\n' "$FPGA_WORK_ROOT"
  else
    target_config_value "$core" FPGA_WORK_ROOT
  fi
}

fpga_bitstream_path() {
  local core="$1"
  local work_root

  work_root="$(fpga_work_root "$core")"
  printf '%s/corejack_corejack_platform_0.1.0.bit\n' "$work_root"
}

fpga_manifest_path() {
  local core="$1"
  local work_root

  work_root="$(fpga_work_root "$core")"
  printf '%s/.corejack_bitstream_manifest\n' "$work_root"
}

core_debug_supported() {
  local core="$1"

  "${PYTHON:-python3.13}" bin/validate_target.py \
    --core "$core" \
    --board "$board" \
    --flow debug \
    --quiet >/dev/null 2>&1
}

design_input_hash() {
  # Shared with bin/write_bitstream_manifest.sh so the recorded and checked
  # hashes cannot drift apart.
  bin/design_input_hash.sh
}

write_fpga_manifest() {
  local core="$1"
  local uart_loader="$2"
  local manifest
  local bitstream
  local core_type

  manifest="$(fpga_manifest_path "$core")"
  bitstream="$(fpga_bitstream_path "$core")"
  core_type="$(target_config_value "$core" CORE_TYPE)"

  if [ ! -f "$bitstream" ]; then
    echo "Error: expected bitstream was not created: $bitstream" >&2
    exit 1
  fi

  bin/write_bitstream_manifest.sh \
    --core "$core" \
    --board "$board" \
    --core-type "$core_type" \
    --uart-loader "$uart_loader" \
    --bitstream "$bitstream" \
    --manifest "$manifest"
}

check_fpga_manifest() {
  local core="$1"
  local expected_uart_loader="$2"
  local manifest
  local bitstream
  local expected_core_type
  local manifest_core=""
  local manifest_board=""
  local manifest_core_type=""
  local manifest_uart_loader="0"
  local manifest_bitstream=""
  local manifest_bitstream_sha256=""
  local manifest_design_hash=""
  local actual_bitstream_sha256=""
  local current_design_hash=""

  manifest="$(fpga_manifest_path "$core")"
  bitstream="$(fpga_bitstream_path "$core")"
  expected_core_type="$(target_config_value "$core" CORE_TYPE)"

  if [ ! -f "$manifest" ]; then
    echo "Error: --skip-bit would program without a matching bitstream manifest." >&2
    echo "Run fpga-bit first for CORE=$core BOARD=$board, or also pass --skip-pgm if the FPGA is already programmed." >&2
    echo "Expected manifest: $manifest" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$manifest"
  manifest_core="${CORE:-}"
  manifest_board="${BOARD:-}"
  manifest_core_type="${CORE_TYPE:-}"
  manifest_uart_loader="${UART_LOADER:-0}"
  manifest_bitstream="${BITSTREAM:-}"
  manifest_bitstream_sha256="${BITSTREAM_SHA256:-}"
  manifest_design_hash="${DESIGN_INPUT_HASH:-}"

  if [ "$manifest_core" != "$core" ] ||
     [ "$manifest_board" != "$board" ] ||
     [ "$manifest_core_type" != "$expected_core_type" ] ||
     [ "$manifest_uart_loader" != "$expected_uart_loader" ] ||
     [ "$manifest_bitstream" != "$bitstream" ]; then
    echo "Error: --skip-bit would program a stale or mismatched bitstream." >&2
    echo "Requested: CORE=$core BOARD=$board CORE_TYPE=$expected_core_type UART_LOADER=$expected_uart_loader" >&2
    echo "Manifest:  CORE=$manifest_core BOARD=$manifest_board CORE_TYPE=$manifest_core_type UART_LOADER=$manifest_uart_loader" >&2
    echo "Run fpga-bit for the requested core/board before programming." >&2
    exit 1
  fi

  if [ ! -f "$bitstream" ]; then
    echo "Error: bitstream listed by manifest does not exist: $bitstream" >&2
    exit 1
  fi

  if [ -n "$manifest_bitstream_sha256" ]; then
    actual_bitstream_sha256="$(sha256sum "$bitstream" | awk '{print $1}')"
    if [ "$actual_bitstream_sha256" != "$manifest_bitstream_sha256" ]; then
      echo "Error: bitstream hash does not match manifest." >&2
      echo "Manifest: $manifest_bitstream_sha256" >&2
      echo "Actual:   $actual_bitstream_sha256" >&2
      echo "Run fpga-bit for the requested core/board before programming." >&2
      exit 1
    fi
  fi

  if [ -n "$manifest_design_hash" ] && [ "$manifest_design_hash" != "unknown" ]; then
    current_design_hash="$(design_input_hash)"
    if [ "$current_design_hash" != "$manifest_design_hash" ]; then
      echo "Error: tracked FPGA design inputs changed after this bitstream manifest was written." >&2
      echo "Manifest DESIGN_INPUT_HASH: $manifest_design_hash" >&2
      echo "Current  DESIGN_INPUT_HASH: $current_design_hash" >&2
      echo "Run fpga-bit for CORE=$core BOARD=$board, or run fpga-manifest only if this is an intentional metadata-only backfill." >&2
      exit 1
    fi
  fi
}

stop_openocd() {
  if [ -n "$openocd_pid" ] && kill -0 "$openocd_pid" 2>/dev/null; then
    kill "$openocd_pid" 2>/dev/null || true
    wait "$openocd_pid" 2>/dev/null || true
  fi
  openocd_pid=""
}

trap 'stop_uart_capture; stop_openocd' EXIT

stop_uart_capture() {
  if [ -n "$uart_pid" ] && kill -0 "$uart_pid" 2>/dev/null; then
    kill "$uart_pid" 2>/dev/null || true
    wait "$uart_pid" 2>/dev/null || true
  fi
  uart_pid=""
}

start_uart_capture() {
  local core="$1"

  if [ -z "$uart_dev" ]; then
    uart_log=""
    return 0
  fi

  if [ ! -e "$uart_dev" ]; then
    echo "Error: UART device does not exist: $uart_dev" >&2
    exit 1
  fi

  uart_log="$log_dir/uart_${firmware}_${board}_${core}.log"
  : > "$uart_log"
  stty -F "$uart_dev" 115200 raw -echo -ixon -ixoff -crtscts
  timeout "$uart_timeout" cat "$uart_dev" > "$uart_log" &
  uart_pid="$!"
  sleep 0.2
}

check_uart_capture() {
  local core="$1"

  if [ -z "$uart_log" ]; then
    return 0
  fi

  stop_uart_capture

  # Expected text comes from cfg/validation/uart_banners.yaml via
  # validate_target.py, so it cannot drift from what the firmware prints.
  local expected=()
  mapfile -t expected < <(uart_banner_lines "$core" debug)
  if [ "${#expected[@]}" -eq 0 ]; then
    echo "Error: could not resolve expected UART banner for CORE=$core." >&2
    exit 1
  fi

  for line in "${expected[@]}"; do
    if ! grep -Fq "$line" "$uart_log"; then
      echo "Error: UART capture missing expected text for CORE=$core: $line" >&2
      echo "UART log: $uart_log" >&2
      sed -n '1,120p' "$uart_log" >&2 || true
      exit 1
    fi
  done

  echo "UART capture matched expected $firmware banner: $uart_log"
}

record_summary() {
  local core="$1"
  local result="$2"
  local bitstream
  local work_root
  local uart_path="-"

  work_root="$(fpga_work_root "$core")"
  if [ "$skip_bit" -eq 1 ] && [ "$skip_pgm" -eq 1 ]; then
    bitstream="-"
  else
    bitstream="$(fpga_bitstream_path "$core")"
  fi
  if [ -n "${uart_log:-}" ]; then
    uart_path="$uart_log"
  fi

  summary_cores+=("$core")
  summary_firmware+=("$firmware")
  summary_work_roots+=("$work_root")
  summary_bitstreams+=("$bitstream")
  summary_uart_logs+=("$uart_path")
  summary_results+=("$result")
}

print_summary() {
  local i

  if [ "${#summary_cores[@]}" -eq 0 ]; then
    return 0
  fi

  echo
  echo "FPGA acceptance summary:"
  printf '  %-10s %-10s %-6s %s\n' "CORE" "FIRMWARE" "RESULT" "ARTIFACTS"
  for i in "${!summary_cores[@]}"; do
    printf '  %-10s %-10s %-6s work_root=%s\n' \
      "${summary_cores[$i]}" "${summary_firmware[$i]}" "${summary_results[$i]}" "${summary_work_roots[$i]}"
    printf '  %-10s %-10s %-6s bitstream=%s\n' "" "" "" "${summary_bitstreams[$i]}"
    printf '  %-10s %-10s %-6s uart_log=%s\n' "" "" "" "${summary_uart_logs[$i]}"
  done
}

run_step_smoke() {
  local core="$1"
  local elf
  local entry_symbol
  local gdb_cmd="${GDB:-}"
  local gdb_log="$log_dir/gdb_step_${board}_${core}.log"

  case "$firmware" in
    baremetal)
      elf="sw/build/fpga/${core}/riscv-multilib/${app}/cmake/${app}/${app}"
      entry_symbol="_entry_point"
      ;;
    zephyr)
      elf="sw/build/zephyr/corejack_${core}_${board}/${zephyr_app}/zephyr/zephyr.elf"
      entry_symbol="__start"
      ;;
  esac

  if [ -z "$gdb_cmd" ]; then
    if [ -x "$repo_root/.tools/riscv/bin/riscv64-unknown-elf-gdb" ]; then
      gdb_cmd="$repo_root/.tools/riscv/bin/riscv64-unknown-elf-gdb"
    elif [ -n "${RISCV:-}" ] && [ -x "${RISCV}/bin/riscv64-unknown-elf-gdb" ]; then
      gdb_cmd="${RISCV}/bin/riscv64-unknown-elf-gdb"
    elif [ -n "${RISCV:-}" ] && [ -x "${RISCV}/bin/riscv-none-elf-gdb" ]; then
      gdb_cmd="${RISCV}/bin/riscv-none-elf-gdb"
    elif command -v riscv64-unknown-elf-gdb >/dev/null 2>&1; then
      gdb_cmd="riscv64-unknown-elf-gdb"
    elif command -v riscv-none-elf-gdb >/dev/null 2>&1; then
      gdb_cmd="riscv-none-elf-gdb"
    else
      echo "Error: no RISC-V GDB found. Source ./sourceme.sh or set GDB." >&2
      exit 1
    fi
  fi

  if ! "$gdb_cmd" "$elf" \
    -batch \
    -ex "target extended-remote localhost:3333" \
    -ex "monitor reset halt" \
    -ex "info registers pc" \
    -ex "load" \
    -ex "set \$pc = (unsigned long)&${entry_symbol}" \
    -ex "info registers pc" \
    -ex "stepi" \
    -ex "info registers pc" \
    -ex "stepi" \
    -ex "info registers pc" \
    -ex "detach" 2>&1 | tee "$gdb_log"; then
    echo "Error: GDB step smoke failed for CORE=$core. Log: $gdb_log" >&2
    exit 1
  fi

  if grep -Eq "Cannot insert hardware breakpoint|Remote failure reply|Command aborted|Cannot access memory|Could not read registers" "$gdb_log"; then
    echo "Error: GDB step smoke reported a debug/remote error for CORE=$core. Log: $gdb_log" >&2
    exit 1
  fi
}

start_openocd() {
  local core="$1"
  openocd_log="$log_dir/openocd_${board}_${core}.log"
  : > "$openocd_log"

  make openocd CORE="$core" BOARD="$board" \
    ${JTAG_ADAPTER:+JTAG_ADAPTER="$JTAG_ADAPTER"} > "$openocd_log" 2>&1 &
  openocd_pid="$!"

  for _ in $(seq 1 100); do
    if grep -Eq "Examination failed|Target not examined|Unsupported DTM version|JTAG scan chain interrogation failed|IR capture error" "$openocd_log"; then
      echo "Error: OpenOCD failed to examine CORE=$core. Log: $openocd_log" >&2
      tail -n 80 "$openocd_log" >&2 || true
      exit 1
    fi
    if grep -q "Examination succeed" "$openocd_log" &&
       grep -q "Listening on port 3333 for gdb connections" "$openocd_log"; then
      return 0
    fi
    if ! kill -0 "$openocd_pid" 2>/dev/null; then
      echo "Error: OpenOCD exited early for CORE=$core. Log: $openocd_log" >&2
      tail -n 80 "$openocd_log" >&2 || true
      exit 1
    fi
    sleep 0.2
  done

  echo "Error: OpenOCD did not become ready for CORE=$core. Log: $openocd_log" >&2
  tail -n 80 "$openocd_log" >&2 || true
  exit 1
}

uart_loader_expect_text() {
  local core="$1"

  # Same source of truth as check_uart_capture(); the loader host tool waits on
  # the single trailing "alive" line rather than the whole banner.
  uart_banner_lines "$core" loader --alive-only
}

run_uart_loader_acceptance() {
  local core="$1"
  local expect

  if [ -z "$uart_dev" ]; then
    echo "Error: UART_DEV/--uart is required for non-debug CORE=$core UART-loader acceptance." >&2
    exit 1
  fi

  uart_log="$log_dir/uart_loader_${firmware}_${board}_${core}.log"
  expect="$(uart_loader_expect_text "$core")"

  if [ "$firmware" = "baremetal" ]; then
    if ! make fpga-uart-load-sw \
      CORE="$core" \
      BOARD="$board" \
      SW_APP="$app" \
      UART_DEV="$uart_dev" \
      UART_CAPTURE_TIMEOUT="$uart_timeout" \
      UART_LOADER_EXPECT="$expect" 2>&1 | tee "$uart_log"; then
      echo "Error: UART-loader bare-metal acceptance failed for CORE=$core. Log: $uart_log" >&2
      exit 1
    fi
  else
    if ! make fpga-uart-load-zephyr \
      CORE="$core" \
      BOARD="$board" \
      ZEPHYR_APP="$zephyr_app" \
      UART_DEV="$uart_dev" \
      UART_CAPTURE_TIMEOUT="$uart_timeout" \
      UART_LOADER_EXPECT="$expect" 2>&1 | tee "$uart_log"; then
      echo "Error: UART-loader Zephyr acceptance failed for CORE=$core. Log: $uart_log" >&2
      exit 1
    fi
  fi
}

for core in $cores; do
  debug_supported=0
  uart_loader=0
  if core_debug_supported "$core"; then
    debug_supported=1
  else
    uart_loader=1
  fi

  echo "==> FPGA acceptance: CORE=$core BOARD=$board FIRMWARE=$firmware DEBUG=$debug_supported UART_LOADER=$uart_loader"

  make validate-target CORE="$core" BOARD="$board"

  if [ "$skip_sim" -eq 0 ]; then
    if [ "$firmware" = "baremetal" ]; then
      make sim-run-sw CORE="$core" BOARD="$board" SW_APP="$app" SIM_TIMEOUT_CYCLES="${SIM_TIMEOUT_CYCLES:-1000000}"
    else
      echo "Skipping sim-run-sw for firmware=zephyr; this acceptance flow checks FPGA/OpenOCD/GDB."
    fi
  fi

  if [ "$skip_bit" -eq 0 ]; then
    make fpga-bit CORE="$core" BOARD="$board" UART_LOADER="$uart_loader"
    write_fpga_manifest "$core" "$uart_loader"
  elif [ "$skip_pgm" -eq 0 ]; then
    check_fpga_manifest "$core" "$uart_loader"
  fi

  if [ "$skip_pgm" -eq 0 ]; then
    check_fpga_manifest "$core" "$uart_loader"
    make fpga-pgm CORE="$core" BOARD="$board"
  fi

  needs_openocd=0
  if [ "$debug_supported" -eq 1 ] && { [ "$skip_run" -eq 0 ] || [ "$skip_step" -eq 0 ]; }; then
    needs_openocd=1
  fi

  if [ "$skip_run" -ne 0 ]; then
    if [ "$firmware" = "baremetal" ]; then
      make sw-build CORE="$core" BOARD="$board" TARGET=fpga SW_APP="$app"
    else
      make zephyr-build CORE="$core" BOARD="$board" ZEPHYR_APP="$zephyr_app"
    fi
  fi

  if [ "$needs_openocd" -eq 1 ]; then
    start_openocd "$core"

    if [ "$skip_run" -eq 0 ]; then
      start_uart_capture "$core"
      if [ "$firmware" = "baremetal" ]; then
        make fpga-run-sw CORE="$core" BOARD="$board" SW_APP="$app" GDB_TIMEOUT="$gdb_timeout"
      else
        make fpga-run-zephyr CORE="$core" BOARD="$board" ZEPHYR_APP="$zephyr_app" GDB_TIMEOUT="$gdb_timeout"
      fi
      check_uart_capture "$core"
    fi

    if [ "$skip_step" -eq 0 ]; then
      run_step_smoke "$core"
    fi

    if [ "$keep_openocd" -eq 0 ]; then
      stop_openocd
    fi
  elif [ "$skip_run" -eq 0 ]; then
    run_uart_loader_acceptance "$core"
  fi

  record_summary "$core" "PASS"
  echo "==> PASS: CORE=$core BOARD=$board"
done

print_summary
echo "FPGA acceptance completed."
