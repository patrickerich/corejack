#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

verible_ref="${VERIBLE_REF:-v0.0-4053-g89d4d98a}"
prefix="${VERIBLE_PREFIX:-${repo_dir}/.tools/verible}"
archive_url="${VERIBLE_ARCHIVE_URL:-}"

required_tools=(
  curl
  tar
)

missing=()
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing+=("${tool}")
  fi
done

if (( ${#missing[@]} )); then
  echo "Missing tools required to install Verible: ${missing[*]}" >&2
  exit 1
fi

if [[ -z "${archive_url}" ]]; then
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "${os}:${arch}" in
    linux:x86_64|linux:amd64)
      asset_arch="x86_64"
      asset="verible-${verible_ref}-linux-static-${asset_arch}.tar.gz"
      ;;
    linux:aarch64|linux:arm64)
      asset_arch="arm64"
      asset="verible-${verible_ref}-linux-static-${asset_arch}.tar.gz"
      ;;
    *)
      echo "Unsupported Verible binary platform: ${os}/${arch}" >&2
      echo "Set VERIBLE_ARCHIVE_URL to a compatible release archive if available." >&2
      exit 1
      ;;
  esac
  archive_url="https://github.com/chipsalliance/verible/releases/download/${verible_ref}/${asset}"
fi

echo "CoreJack Verible binary install"
echo "  ref:     ${verible_ref}"
echo "  url:     ${archive_url}"
echo "  prefix:  ${prefix}"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p "${prefix}" "${repo_dir}/.tools"
touch "${repo_dir}/.tools/FUSESOC_IGNORE"

curl -fsSL "${archive_url}" -o "${tmp}/verible.tar.gz"
mkdir -p "${tmp}/unpack"
tar -xzf "${tmp}/verible.tar.gz" -C "${tmp}/unpack"

bin_dir="$(find "${tmp}/unpack" -type d -path '*/bin' | head -n 1)"
if [[ -z "${bin_dir}" ]]; then
  echo "No bin directory found in Verible archive." >&2
  exit 1
fi

rm -rf "${prefix:?}/bin"
mkdir -p "${prefix}/bin"
for tool in \
  verible-verilog-format \
  verible-verilog-lint \
  verible-verilog-syntax \
  verible-verilog-ls \
  verible-verilog-project
do
  if [[ -x "${bin_dir}/${tool}" ]]; then
    install -m 755 "${bin_dir}/${tool}" "${prefix}/bin/${tool}"
  fi
done

if [[ ! -x "${prefix}/bin/verible-verilog-lint" ]]; then
  echo "Installed archive did not contain verible-verilog-lint." >&2
  exit 1
fi

echo
echo "Installed Verible under: ${prefix}"
echo "Add to PATH:"
echo "  export PATH=\"${prefix}/bin:\$PATH\""
echo
"${prefix}/bin/verible-verilog-lint" --version
