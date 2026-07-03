#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

verilator_repo="${VERILATOR_REPO:-https://github.com/verilator/verilator.git}"
verilator_ref="${VERILATOR_REF:-v5.050}"
verilator_commit="${VERILATOR_COMMIT:-848d926ebd4addacacd294dc84e35d9d4ae8078c}"
src_dir="${VERILATOR_SRC:-${repo_dir}/.tools/src/verilator}"
prefix="${VERILATOR_PREFIX:-${repo_dir}/.tools/verilator}"
jobs="${VERILATOR_JOBS:-$(nproc 2>/dev/null || echo 4)}"

required_tools=(
  git
  autoconf
  flex
  bison
  help2man
  perl
  make
)

if ! command -v "${CXX:-g++}" >/dev/null 2>&1; then
  required_tools+=(g++)
fi

missing=()
for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    missing+=("${tool}")
  fi
done

if (( ${#missing[@]} )); then
  echo "Missing tools required to build Verilator: ${missing[*]}" >&2
  echo "Install the host packages for these tools and rerun this target." >&2
  exit 1
fi

echo "CoreJack Verilator build"
echo "  repo:   ${verilator_repo}"
echo "  ref:    ${verilator_ref}"
if [[ -n "${verilator_commit}" ]]; then
  echo "  commit: ${verilator_commit}"
fi
echo "  source: ${src_dir}"
echo "  prefix: ${prefix}"
echo "  jobs:   ${jobs}"

mkdir -p "$(dirname "${src_dir}")" "$(dirname "${prefix}")"
touch "${repo_dir}/.tools/FUSESOC_IGNORE"

if [[ ! -d "${src_dir}/.git" ]]; then
  git clone "${verilator_repo}" "${src_dir}"
else
  git -C "${src_dir}" fetch --tags origin
fi

git -C "${src_dir}" checkout "${verilator_ref}"
actual_commit="$(git -C "${src_dir}" rev-parse HEAD)"
if [[ -n "${verilator_commit}" && "${actual_commit}" != "${verilator_commit}" ]]; then
  echo "Resolved Verilator commit ${actual_commit}, expected ${verilator_commit}." >&2
  exit 1
fi
echo "  resolved commit: ${actual_commit}"

(
  cd "${src_dir}"
  autoconf
  ./configure --prefix="${prefix}"
  make -j"${jobs}"
  make install
)

echo
echo "Installed Verilator under: ${prefix}"
echo "Add to PATH:"
echo "  export PATH=\"${prefix}/bin:\$PATH\""

if [[ -x "${prefix}/bin/verilator" ]]; then
  echo
  "${prefix}/bin/verilator" --version
fi
