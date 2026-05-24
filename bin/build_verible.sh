#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

verible_ref="${VERIBLE_REF:-v0.0-4053-g89d4d98a}"
prefix="${VERIBLE_PREFIX:-${repo_dir}/.tools/verible}"
archive_url="${VERIBLE_ARCHIVE_URL:-}"
archive_sha256="${VERIBLE_ARCHIVE_SHA256:-}"

required_tools=(
  curl
  sha256sum
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
      archive_sha256="${archive_sha256:-${VERIBLE_SHA256_LINUX_X86_64:-1edc1f29c70d74213ed373e727183802d5a733e23f9ab9c74462f5b18b76f2c0}}"
      ;;
    linux:aarch64|linux:arm64)
      asset_arch="arm64"
      asset="verible-${verible_ref}-linux-static-${asset_arch}.tar.gz"
      archive_sha256="${archive_sha256:-${VERIBLE_SHA256_LINUX_ARM64:-e6184011e93eb843fe0b5f1ecc60dcb06eec0ca05784f5caff1a17814068bca1}}"
      ;;
    *)
      echo "Unsupported Verible binary platform: ${os}/${arch}" >&2
      echo "Set VERIBLE_ARCHIVE_URL to a compatible release archive if available." >&2
      exit 1
      ;;
  esac
  archive_url="https://github.com/chipsalliance/verible/releases/download/${verible_ref}/${asset}"
fi

if [[ -z "${archive_sha256}" ]]; then
  echo "No SHA256 configured for Verible archive: ${archive_url}" >&2
  echo "Set VERIBLE_ARCHIVE_SHA256 when overriding VERIBLE_ARCHIVE_URL." >&2
  exit 1
fi

echo "CoreJack Verible binary install"
echo "  ref:     ${verible_ref}"
echo "  url:     ${archive_url}"
echo "  sha256:  ${archive_sha256}"
echo "  prefix:  ${prefix}"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp}"
}
trap cleanup EXIT

mkdir -p "${prefix}" "${repo_dir}/.tools"
touch "${repo_dir}/.tools/FUSESOC_IGNORE"

curl -fsSL "${archive_url}" -o "${tmp}/verible.tar.gz"
printf '%s  %s\n' "${archive_sha256}" "${tmp}/verible.tar.gz" | sha256sum -c -
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
