#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "${script_dir}/.." && pwd)"

toolchain_repo="${RISCV_GNU_TOOLCHAIN_REPO:-https://github.com/riscv-collab/riscv-gnu-toolchain.git}"
toolchain_ref="${RISCV_GNU_TOOLCHAIN_REF:-2026.05.19}"
toolchain_commit="${RISCV_GNU_TOOLCHAIN_COMMIT:-96e1c125620ec403962c8536ecbbde20878c5e44}"
src_dir="${RISCV_GNU_TOOLCHAIN_SRC:-${repo_dir}/.tools/src/riscv-gnu-toolchain}"
prefix="${RISCV_TOOLCHAIN_PREFIX:-${repo_dir}/.tools/riscv}"
jobs="${RISCV_TOOLCHAIN_JOBS:-$(nproc 2>/dev/null || echo 4)}"
multilib_generator="${RISCV_MULTILIB_GENERATOR:-rv32i-ilp32--;rv32imc-ilp32--;rv32imcb-ilp32--;rv64imc-lp64--;rv64gc-lp64d--}"

echo "CoreJack RISC-V GNU toolchain build"
echo "  repo:   ${toolchain_repo}"
echo "  ref:    ${toolchain_ref}"
if [[ -n "${toolchain_commit}" ]]; then
  echo "  commit: ${toolchain_commit}"
fi
echo "  source: ${src_dir}"
echo "  prefix: ${prefix}"
echo "  jobs:   ${jobs}"

if [[ -n "${multilib_generator}" ]]; then
  echo "  multilib generator: ${multilib_generator}"
else
  echo "  multilib: default upstream set"
fi

mkdir -p "$(dirname "${src_dir}")" "$(dirname "${prefix}")"
touch "${repo_dir}/.tools/FUSESOC_IGNORE"

if [[ ! -d "${src_dir}/.git" ]]; then
  # Clone without --recursive so the initial fetch can never fail on a
  # submodule pin; submodules are initialized below with dejagnu skipped.
  git clone "${toolchain_repo}" "${src_dir}"
else
  git -C "${src_dir}" fetch --tags origin
fi

git -C "${src_dir}" checkout "${toolchain_ref}"
actual_commit="$(git -C "${src_dir}" rev-parse HEAD)"
if [[ -n "${toolchain_commit}" && "${actual_commit}" != "${toolchain_commit}" ]]; then
  echo "Resolved RISC-V GNU toolchain commit ${actual_commit}, expected ${toolchain_commit}." >&2
  exit 1
fi
echo "  resolved commit: ${actual_commit}"

# dejagnu is a test-only submodule used by `make check`, not by `make newlib`.
# Its upstream (git.savannah.gnu.org) occasionally prunes the pinned commit and
# fails with "Server does not allow request for unadvertised object". Skip it
# so the toolchain build is not held hostage by an unrelated test pin.
# See docs/tooling.md for the full reasoning.
echo "  note: dejagnu submodule intentionally skipped (test-only; upstream pin volatile)"
git -C "${src_dir}" submodule deinit -f dejagnu 2>/dev/null || true
git -C "${src_dir}" -c submodule.dejagnu.update=none submodule update --init --recursive

configure_args=(
  "--prefix=${prefix}"
)

if [[ -n "${multilib_generator}" ]]; then
  configure_args+=("--with-multilib-generator=${multilib_generator}")
else
  configure_args+=("--enable-multilib")
fi

(
  cd "${src_dir}"
  ./configure "${configure_args[@]}"
  make -j"${jobs}" newlib
)

echo
echo "Installed toolchain under: ${prefix}"
echo "Add to PATH:"
echo "  export PATH=\"${prefix}/bin:\$PATH\""

if [[ -x "${prefix}/bin/riscv64-unknown-elf-gcc" ]]; then
  echo
  echo "Available multilibs:"
  "${prefix}/bin/riscv64-unknown-elf-gcc" --print-multi-lib
fi
