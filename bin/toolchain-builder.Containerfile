# Build environment for bin/build_riscv_toolchain.sh.
#
# Exists to lower the artifact's glibc floor. Built natively on a modern host,
# the toolchain links against that host's glibc and then refuses to start on
# older CI runners. Ubuntu 22.04 ships glibc 2.35, which every current GitHub
# runner satisfies, so an artifact built here runs everywhere we care about --
# including back on the development host, since glibc is backward compatible.
#
# Used via `make toolchain-riscv-container`; see docs/source/tooling.md.

# Pinned by digest, not by tag: `22.04` is rebuilt for security updates and so
# names different bytes over time. Same discipline as pinning the toolchain to a
# commit rather than a tag. To bump deliberately:
#   podman pull docker.io/library/ubuntu:22.04
#   podman image inspect docker.io/library/ubuntu:22.04 --format '{{index .RepoDigests 0}}'
# then edit the line below. Digest below is ubuntu:22.04 as of 2026-08-29.
FROM docker.io/library/ubuntu@sha256:2edbbc5dc405e9612ba3584ce95480277e3eb374407b5505fe26f17df77c7dbc

ENV DEBIAN_FRONTEND=noninteractive

# First group: riscv-gnu-toolchain's documented Ubuntu prerequisites, minus the
# packages only its QEMU target needs (cmake, ninja, libglib2.0-dev, libslirp)
# -- CoreJack builds `make newlib`, never QEMU.
# `gettext` is not in upstream's documented list but is required: without
# `msgfmt`, binutils/gcc/gdb fail their install step on missing po/*.gmo.
# Second group: what bin/build_riscv_toolchain.sh itself calls -- `file` for the
# text-only residual-path audit, `xz-utils` for the tarball, `binutils` for the
# objdump ABI-floor report.
RUN apt-get update && apt-get install -y --no-install-recommends \
      autoconf automake autotools-dev bc bison build-essential curl flex gawk \
      git gettext gperf libexpat1-dev libgmp-dev libmpc-dev libmpfr-dev libtool \
      patchutils python3 texinfo zlib1g-dev ca-certificates \
      file xz-utils binutils \
 && rm -rf /var/lib/apt/lists/*
