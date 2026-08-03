#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bin/write_bitstream_manifest.sh --core <core> --board <board> --core-type <n> --bitstream <path> --manifest <path> [--uart-loader <0|1>] [--best-effort-timestamp]

Write a CoreJack FPGA bitstream manifest with build provenance.

Use --best-effort-timestamp only when backfilling an existing bitstream whose
exact build commit was not recorded at generation time.
EOF
}

core=""
board=""
core_type=""
bitstream=""
manifest=""
best_effort_timestamp=0
uart_loader="${UART_LOADER:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --core)
      core="${2:?missing value for --core}"
      shift 2
      ;;
    --board)
      board="${2:?missing value for --board}"
      shift 2
      ;;
    --core-type)
      core_type="${2:?missing value for --core-type}"
      shift 2
      ;;
    --bitstream)
      bitstream="${2:?missing value for --bitstream}"
      shift 2
      ;;
    --manifest)
      manifest="${2:?missing value for --manifest}"
      shift 2
      ;;
    --uart-loader)
      uart_loader="${2:?missing value for --uart-loader}"
      shift 2
      ;;
    --best-effort-timestamp)
      best_effort_timestamp=1
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

if [ -z "$core" ] || [ -z "$board" ] || [ -z "$core_type" ] || [ -z "$bitstream" ] || [ -z "$manifest" ]; then
  echo "Error: --core, --board, --core-type, --bitstream, and --manifest are required" >&2
  usage >&2
  exit 2
fi

case "$uart_loader" in
  0|1)
    ;;
  *)
    echo "Error: --uart-loader must be 0 or 1, got '$uart_loader'" >&2
    exit 2
    ;;
esac

if [ ! -f "$bitstream" ]; then
  echo "Error: bitstream does not exist: $bitstream" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

bitstream_abs="$(realpath "$bitstream")"
manifest_abs="$(realpath -m "$manifest")"
bitstream_mtime="$(stat -c '%Y' "$bitstream_abs")"
bitstream_sha256="$(sha256sum "$bitstream_abs" | awk '{print $1}')"
manifest_created_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

git_head="$(git rev-parse HEAD)"
git_describe="$(git describe --always --dirty --broken 2>/dev/null || printf '%s' "$git_head")"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  git_dirty=1
else
  git_dirty=0
fi

if [ "$best_effort_timestamp" -eq 1 ]; then
  git_commit="$(git log -1 --format=%H --before="@$bitstream_mtime" HEAD 2>/dev/null || true)"
  if [ -z "$git_commit" ]; then
    git_commit="$git_head"
  fi
  git_commit_mode="best_effort_bitstream_timestamp"
else
  git_commit="$git_head"
  git_commit_mode="exact_current_head"
fi

vivado_version="unknown"
if command -v vivado >/dev/null 2>&1; then
  vivado_version="$(vivado -version 2>/dev/null | sed -n '1p' || true)"
  if [ -z "$vivado_version" ]; then
    vivado_version="unknown"
  fi
fi

# Shared with bin/fpga_debug_acceptance.sh so the recorded and checked hashes
# cannot drift apart. See bin/design_input_hash.sh for the tracked file set.
design_hash="$("$(dirname "${BASH_SOURCE[0]}")/design_input_hash.sh")"
if [ -z "$design_hash" ]; then
  design_hash="unknown"
fi

mkdir -p "$(dirname "$manifest_abs")"
{
  printf 'MANIFEST_VERSION=2\n'
  printf 'CORE=%s\n' "$core"
  printf 'BOARD=%s\n' "$board"
  printf 'CORE_TYPE=%s\n' "$core_type"
  printf 'UART_LOADER=%s\n' "$uart_loader"
  printf 'BITSTREAM=%s\n' "$bitstream_abs"
  printf 'BITSTREAM_MTIME_EPOCH=%s\n' "$bitstream_mtime"
  printf 'BITSTREAM_SHA256=%s\n' "$bitstream_sha256"
  printf 'MANIFEST_CREATED_UTC=%s\n' "$manifest_created_utc"
  printf 'GIT_COMMIT=%s\n' "$git_commit"
  printf 'GIT_COMMIT_MODE=%s\n' "$git_commit_mode"
  printf 'GIT_HEAD_AT_MANIFEST=%s\n' "$git_head"
  printf 'GIT_DESCRIBE_AT_MANIFEST=%s\n' "$git_describe"
  printf 'GIT_DIRTY_AT_MANIFEST=%s\n' "$git_dirty"
  printf 'DESIGN_INPUT_HASH=%s\n' "$design_hash"
  printf 'VIVADO_VERSION=%q\n' "$vivado_version"
} > "$manifest_abs"

echo "Wrote bitstream manifest: $manifest_abs"
