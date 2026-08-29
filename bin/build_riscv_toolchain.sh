#!/usr/bin/env bash
# Build, package, and install the CoreJack RISC-V GNU toolchain.
#
# The toolchain is always installed by unpacking the packaged tarball, never by
# using the raw build tree directly. That keeps a local checkout byte-identical
# to the artifact published for CI, so there is no "works here, fails there"
# gap between what a contributor tests with and what CI downloads.
#
# Upstream bakes its --prefix into linker scripts, libtool archives, and gdb
# autoload scripts. GCC itself derives paths from the driver's location at
# runtime, so the binaries relocate unaided, but those text files do not. They
# are normalised here, and the result must prove it relocates -- by compiling
# every multilib from a throwaway path -- before a tarball is emitted.
#
# Usage: build_riscv_toolchain.sh [--keep] [--skip-build] [--jobs N]
#   --keep        leave the tarball and .sha256 in .tools/dist for upload
#   --skip-build  re-package an existing build instead of rebuilding
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
tuple="${RISCV_TOOLCHAIN_TUPLE:-riscv64-unknown-elf}"
dist_dir="${RISCV_TOOLCHAIN_DIST_DIR:-${repo_dir}/.tools/dist}"

keep_dist="${RISCV_TOOLCHAIN_KEEP_DIST:-0}"
skip_build=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep) keep_dist=1 ;;
    --skip-build) skip_build=1 ;;
    --jobs) jobs="$2"; shift ;;
    --jobs=*) jobs="${1#*=}" ;;
    -h|--help) sed -n '/^# Usage:/,/^#   --skip-build/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Error: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

echo "CoreJack RISC-V GNU toolchain"
echo "  repo:   ${toolchain_repo}"
echo "  ref:    ${toolchain_ref}"
[[ -n "${toolchain_commit}" ]] && echo "  commit: ${toolchain_commit}"
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

# ----------------------------------------------------------------- build ----
if [[ "${skip_build}" == "0" ]]; then
  if [[ ! -d "${src_dir}/.git" ]]; then
    # Clone without --recursive so the initial fetch can never fail on a
    # submodule pin; unneeded submodules are skipped when they are initialized
    # below.
    git clone "${toolchain_repo}" "${src_dir}"
  elif [[ -n "${toolchain_commit}" ]] \
       && git -C "${src_dir}" cat-file -e "${toolchain_commit}^{commit}" 2>/dev/null; then
    # The pin is already in the local clone, so a fetch cannot change what gets
    # built. Fetching anyway recurses into submodules hosted on sourceware.org,
    # which rate-limits (HTTP 429) and then fails the build for no gain. Only
    # reach for the network when the pinned commit is genuinely missing.
    echo "  pinned commit already present; skipping fetch"
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

  # Submodules that `make newlib` never reaches. Cloning them buys nothing and
  # puts the build at the mercy of hosts that are not GitHub:
  #   dejagnu - test framework for `make check`. Its upstream
  #             (git.savannah.gnu.org) prunes unadvertised commits, failing with
  #             "Server does not allow request for unadvertised object".
  #   musl    - only reachable from the separate `musl:` target in upstream's
  #             Makefile.in; `newlib:` depends on gcc/binutils/newlib/gdb alone.
  #             git.musl-libc.org was unreachable on 2026-08-29.
  # See docs/source/tooling.md for the full reasoning.
  skip_submodules=(dejagnu musl)
  skip_args=()
  for sm in "${skip_submodules[@]}"; do
    echo "  note: ${sm} submodule intentionally skipped (unused by 'make newlib')"
    git -C "${src_dir}" submodule deinit -f "${sm}" 2>/dev/null || true
    skip_args+=(-c "submodule.${sm}.update=none")
  done
  git -C "${src_dir}" "${skip_args[@]}" submodule update --init --recursive

  configure_args=("--prefix=${prefix}")
  if [[ -n "${multilib_generator}" ]]; then
    configure_args+=("--with-multilib-generator=${multilib_generator}")
  else
    configure_args+=("--enable-multilib")
  fi

  echo "==> building from source (this takes a while)"
  (
    cd "${src_dir}"
    ./configure "${configure_args[@]}"
    make -j"${jobs}" newlib
  )
else
  echo "==> skipping build (--skip-build)"
  # The build step is what verifies the tree matches the pin. Skipping it means
  # packaging whatever is already installed, which may predate a pin bump -- so
  # record the commit as unverified rather than implying it was checked.
  actual_commit="$(git -C "${src_dir}" rev-parse HEAD 2>/dev/null || echo unknown)"
  pin_state="UNVERIFIED (--skip-build; tree not re-checked against the pin)"
  if [[ "${actual_commit}" != "${toolchain_commit}" ]]; then
    echo "  warning: installed tree may not match ${toolchain_ref} (${toolchain_commit})" >&2
    echo "           source tree is at ${actual_commit}" >&2
  fi
fi
pin_state="${pin_state:-verified against ${toolchain_ref}}"

test -x "${prefix}/bin/${tuple}-gcc" || {
  echo "Error: no toolchain at ${prefix}. Run without --skip-build." >&2; exit 1; }

# --------------------------------------------------------------- package ----
version="$("${prefix}/bin/${tuple}-gcc" -dumpversion)"
build_prefix="$(cd "${prefix}" && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "${stage}"' EXIT
work="${stage}/${tuple}"

echo "==> staging build output"
cp -a "${build_prefix}" "${work}"

echo "==> normalising baked-in paths"

# 1. Linker scripts: "=" is ld's sysroot marker, so "=/lib" follows the
#    --sysroot gcc computes from the driver rather than pinning an absolute dir.
find "${work}/${tuple}/lib/ldscripts" -type f 2>/dev/null -print0 \
  | xargs -0 --no-run-if-empty sed -i "s|SEARCH_DIR(\"${build_prefix}/${tuple}|SEARCH_DIR(\"=|g"

# 2. libtool archives describe host link lines for shared libraries. A
#    bare-metal cross toolchain links the .a directly and never consults them.
find "${work}" -name '*.la' -delete

# 3. gdb autoload scripts: recompute their absolute paths from __file__.
python3 - "${work}" "${build_prefix}" <<'PY'
import os, re, sys
work, prefix = sys.argv[1], sys.argv[2]
header = ("import os as _os\n"
          "_here = _os.path.dirname(_os.path.realpath(__file__))\n")
for root, _, files in os.walk(work):
    for name in files:
        if not name.endswith('.py'):
            continue
        path = os.path.join(root, name)
        with open(path) as fh:
            text = fh.read()
        if prefix not in text:
            continue
        def to_rel(m):
            # Map the baked-in absolute path into the staging tree before
            # measuring, or relpath walks back out to the real build location.
            staged = work + m.group(2)[len(prefix):]
            return f"{m.group(1)} = _os.path.join(_here, {os.path.relpath(staged, root)!r})"
        with open(path, 'w') as fh:
            fh.write(header + re.sub(rf"(\w+)\s*=\s*'({re.escape(prefix)}[^']*)'", to_rel, text))
PY

# 4. Informational only (they record the configure line), but an absolute path
#    left here would defeat the audit below.
for f in "${work}/lib/gcc/${tuple}/${version}/plugin/include/configargs.h" \
         "${work}/lib/gcc/${tuple}/${version}/install-tools/mkheaders.conf" \
         "${work}/libexec/gcc/${tuple}/${version}/install-tools/mkheaders"; do
  [[ -f "$f" ]] || continue
  sed -i "s|${build_prefix}|@TOOLCHAIN_PREFIX@|g" "$f"
done

echo "==> stripping host binaries (target archives left intact)"
find "${work}" -type f -executable -print0 | while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in
    *"ELF 64-bit LSB"*x86-64*) strip --strip-unneeded "$f" 2>/dev/null || true ;;
  esac
done

# Audit text files only. GCC deliberately embeds its configure-time prefix into
# the binaries as a fallback and then overrides it at runtime from the driver's
# own location, so a hit inside an ELF is expected and harmless. A hit in a file
# read as text is not: ldscripts and autoload scripts are consumed literally.
echo "==> auditing text files for residual build paths"
residual=""
while IFS= read -r f; do
  case "$(file -b --mime-type "$f")" in
    text/*|application/json|application/x-shellscript) residual="${residual}${f}"$'\n' ;;
  esac
done < <(grep -rl "${build_prefix}" "${work}" 2>/dev/null || true)
if [[ -n "${residual}" ]]; then
  echo "Error: build prefix still present in text files:" >&2
  printf '%s' "${residual}" | sed "s|^${work}|<toolchain>|" >&2
  exit 1
fi
echo "    clean (binaries may retain it as an overridden fallback)"

echo "==> relocation self-test"
probe="${stage}/probe"
mv "${work}" "${probe}"
cat > "${stage}/t.c" <<'EOF'
#include <stdint.h>
#include <string.h>
volatile uint32_t sink;
int main(void) { char b[8]; memset(b, 0x5a, sizeof b); sink = b[3]; return 0; }
EOF
"${probe}/bin/${tuple}-gcc" -print-multi-lib | while IFS=';' read -r dir opts; do
  # -print-multi-lib encodes each option with a leading '@' meaning '-',
  # e.g. "rv32i/ilp32;@march=rv32i@mabi=ilp32".
  flags="$(printf '%s' "${opts}" | sed 's/@/ -/g')"
  printf '    %-46s ' "${dir}"
  if "${probe}/bin/${tuple}-gcc" ${flags} -specs=nosys.specs -O2 \
       -o "${stage}/t.elf" "${stage}/t.c" 2>"${stage}/err"; then
    echo "ok"
  else
    echo "FAILED"; sed 's/^/      /' "${stage}/err" >&2; exit 1
  fi
done
mv "${probe}" "${work}"

# Provenance travels with the artifact: it identifies which upstream tree the
# binaries came from, and satisfies the GPLv3 corresponding-source pointer for
# a published tarball.
cat > "${work}/MANIFEST" <<MANIFEST_EOF
CoreJack RISC-V GNU toolchain
gcc version:        ${version}
upstream repo:      ${toolchain_repo}
upstream ref:       ${toolchain_ref}
upstream commit:    ${actual_commit:-unknown}
pin state:          ${pin_state}
multilib generator: ${multilib_generator}
built:              $(date -u +%Y-%m-%dT%H:%M:%SZ)
built by:           bin/build_riscv_toolchain.sh
MANIFEST_EOF

mkdir -p "${dist_dir}"
tarball="${dist_dir}/corejack-riscv-toolchain-${version}-x86_64.tar.xz"
echo "==> packing $(basename "${tarball}")"
tar -C "${stage}" -cf - "${tuple}" | xz -T0 -6 > "${tarball}"
( cd "${dist_dir}" && sha256sum "$(basename "${tarball}")" > "$(basename "${tarball}").sha256" )

# --------------------------------------------------------------- install ----
# Install by unpacking the artifact, so what is used locally is exactly what
# CI downloads -- including the normalisation and stripping.
echo "==> installing from the packaged artifact"
rm -rf "${prefix}.new" "${prefix}.old"
mkdir -p "${prefix}.new"
tar -C "${prefix}.new" -xf "${tarball}"
[[ -d "${prefix}" ]] && mv "${prefix}" "${prefix}.old"
mv "${prefix}.new/${tuple}" "${prefix}"
rmdir "${prefix}.new"
rm -rf "${prefix}.old"

if [[ "${keep_dist}" == "1" ]]; then
  echo
  echo "Artifact kept for upload:"
  echo "  $(du -h "${tarball}" | cut -f1)  ${tarball}"
  cat "${tarball}.sha256"
  echo
  floor="$(find "${prefix}/libexec" -name 'cc1' -print -quit | xargs objdump -T 2>/dev/null \
    | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)"
  echo "Host ABI floor -- a runner older than this cannot use the tarball:"
  echo "  glibc ${floor:-unknown}"
  # Only advise the container when the floor is actually too high to publish.
  # `make toolchain-riscv-container` builds against Ubuntu 22.04 (glibc 2.35),
  # which every current GitHub runner satisfies; printing the advice after such
  # a build would be telling the user to do what they just did.
  if [[ -n "${floor}" ]] \
     && [[ "$(printf '%s\nGLIBC_2.35\n' "${floor}" | sort -V | tail -1)" != "GLIBC_2.35" ]] \
     && [[ "${floor}" != "GLIBC_2.35" ]]; then
    echo "  Above the glibc 2.35 that CI runners provide. Rebuild with:"
    echo "    make toolchain-riscv-container"
  fi
  echo "  The tarball also needs libmpc.so.3 and libmpfr.so.6 on the host."
else
  rm -f "${tarball}" "${tarball}.sha256"
  rmdir "${dist_dir}" 2>/dev/null || true
fi

echo
echo "Installed toolchain under: ${prefix}"
echo "Add to PATH:"
echo "  export PATH=\"${prefix}/bin:\$PATH\""
echo
echo "Available multilibs:"
"${prefix}/bin/${tuple}-gcc" --print-multi-lib
