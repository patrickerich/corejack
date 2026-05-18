#!/usr/bin/env python3
"""Create a conservative CoreJack RISC-V core scaffold."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PLATFORM_PKG = "rtl/pkg/platform_pkg.sv"
CORE_FILE = "corejack.core"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def require_identifier(name: str, field: str) -> None:
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        fail(f"{field} must match [a-z][a-z0-9_]*, got '{name}'")


def core_enum_name(core: str) -> str:
    return "CORE_" + re.sub(r"[^A-Za-z0-9]+", "_", core).upper()


def write_new(path: Path, content: str, repo_root: Path) -> None:
    if path.exists():
        fail(f"refusing to overwrite existing path: {path.relative_to(repo_root)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def yaml_top_list_contains(text: str, key: str, item: str) -> bool:
    lines = text.splitlines()
    in_list = False
    base_indent = 0
    for line in lines:
        key_match = re.match(rf"^(\s*){re.escape(key)}:\s*$", line)
        if key_match:
            in_list = True
            base_indent = len(key_match.group(1))
            continue
        if in_list:
            indent = len(line) - len(line.lstrip())
            stripped = line.strip()
            if stripped and indent <= base_indent:
                break
            if stripped == f"- {item}":
                return True
    return False


def append_yaml_top_list_item(text: str, key: str, item: str) -> str:
    if yaml_top_list_contains(text, key, item):
        return text

    lines = text.splitlines()
    out: list[str] = []
    in_list = False
    inserted = False
    base_indent = 0

    for line in lines:
        if not inserted:
            key_match = re.match(rf"^(\s*){re.escape(key)}:\s*$", line)
            if key_match:
                in_list = True
                base_indent = len(key_match.group(1))
                out.append(line)
                continue
            if in_list:
                stripped = line.strip()
                indent = len(line) - len(line.lstrip())
                if stripped and indent <= base_indent:
                    out.append(f"{' ' * (base_indent + 2)}- {item}")
                    inserted = True
                    in_list = False
                elif not stripped:
                    out.append(f"{' ' * (base_indent + 2)}- {item}")
                    inserted = True
                    in_list = False
        out.append(line)

    if in_list and not inserted:
        out.append(f"{' ' * (base_indent + 2)}- {item}")
        inserted = True

    if not inserted:
        fail(f"could not find YAML list '{key}'")
    return "\n".join(out) + "\n"


def existing_core_type_values(text: str) -> list[int]:
    match = re.search(
        r"typedef\s+enum\s+int\s+unsigned\s*\{(?P<body>.*?)\}\s*core_type_e\s*;",
        text,
        flags=re.S,
    )
    if not match:
        fail("could not find platform_pkg::core_type_e")
    return [int(value) for _, value in re.findall(r"\b(CORE_[A-Z0-9_]+)\s*=\s*([0-9]+)", match.group("body"))]


def next_core_type(repo_root: Path) -> int:
    text = (repo_root / PLATFORM_PKG).read_text(encoding="utf-8")
    values = existing_core_type_values(text)
    return max(values, default=-1) + 1


def update_platform_pkg(repo_root: Path, args: argparse.Namespace) -> None:
    path = repo_root / PLATFORM_PKG
    text = path.read_text(encoding="utf-8")
    enum_name = core_enum_name(args.core)
    if re.search(rf"\b{re.escape(enum_name)}\b", text):
        fail(f"{enum_name} already exists in {PLATFORM_PKG}")

    pattern = r"(?P<indent>\s*)(?P<last>CORE_[A-Z0-9_]+\s*=\s*[0-9]+)(?P<trailing>\s*)\n(?P<close>\s*\}\s*core_type_e\s*;)"
    match = re.search(pattern, text)
    if not match:
        fail("could not find final core_type_e enum entry")

    replacement = (
        f"{match.group('indent')}{match.group('last')},\n"
        f"{match.group('indent')}{enum_name} = {args.core_type}{match.group('trailing')}\n"
        f"{match.group('close')}"
    )
    path.write_text(text[: match.start()] + replacement + text[match.end() :], encoding="utf-8")


def core_descriptor(args: argparse.Namespace) -> str:
    adapter = f"corejack_{args.core}_{args.integration_suffix}_adapter"
    adapter_file = f"rtl/cores/{adapter}.sv"
    return f"""name: {args.core}
display_name: {args.display_name}

integration:
  sim: planned
  fpga: planned
  debug: planned

adapter:
  module: {adapter}
  file: {adapter_file}

platform:
  core_type: {args.core_type}
  integration: {args.platform_integration}

wrapper:
  module: {args.core}_wrapper

fusesoc:
  sim_target: sw-sim
  core_flag: core_{args.core}

isa:
  xlen: {args.xlen}
  march: {args.march}
  mabi: {args.mabi}

reset:
  boot_addr: 0x80000000
  mtvec_addr: 0x80000000

debug:
  supported: false

buses:
  instruction: {args.instruction_bus}
  data: {args.data_bus}

clocking:
  validated_min_hz: 0
  validated_max_hz: 0

software:
  default_target: sim
  toolchain: riscv-multilib
  zephyr:
    status: planned

compatible_boards:
  - {args.board}
"""


def core_fusesoc(args: argparse.Namespace) -> str:
    adapter = f"corejack_{args.core}_{args.integration_suffix}_adapter"
    return f"""CAPI=2:

name: corejack:cores:{args.core}:0.1.0
description: {args.display_name} RTL and CoreJack adapter used by the CoreJack platform

filesets:
  rtl:
    files:
      - rtl/cores/{adapter}.sv
    file_type: systemVerilogSource

targets:
  default:
    filesets:
      - rtl
"""


def core_adapter(args: argparse.Namespace) -> str:
    adapter = f"corejack_{args.core}_{args.integration_suffix}_adapter"
    return f"""// Placeholder adapter for {args.display_name}.
//
// This scaffold is intentionally not wired into corejack_core_region. Replace
// this module with the real core protocol adapter before attempting simulation
// or FPGA support promotion.
module {adapter};
endmodule
"""


def update_corejack_core(repo_root: Path, args: argparse.Namespace) -> None:
    path = repo_root / CORE_FILE
    text = path.read_text(encoding="utf-8")
    flag = f"core_{args.core}"
    fileset = f"{flag}_rtl"
    define = f"COREJACK_CORE_{re.sub(r'[^A-Za-z0-9]+', '_', args.core).upper()}"

    if f"  {fileset}:" in text:
        fail(f"{fileset} already exists in {CORE_FILE}")
    if f"{flag} ? (" in text:
        fail(f"{flag} already exists in {CORE_FILE}")

    marker = "\n  core_region_rtl:\n"
    block = f"""
  {fileset}:
    depend:
      - corejack:cores:{args.core}:0.1.0
"""
    if marker not in text:
        fail(f"could not find core_region_rtl marker in {CORE_FILE}")
    text = text.replace(marker, block + marker, 1)

    define_marker = "        - core_cvw ? (-DCOREJACK_CORE_CVW)\n"
    if define_marker not in text:
        fail(f"could not find sw-sim core define marker in {CORE_FILE}")
    text = text.replace(
        define_marker,
        f"{define_marker}        - {flag} ? (-D{define})\n",
        1,
    )

    sw_marker = "      - core_cvw ? (core_cvw_rtl)\n      - core_region ? (core_region_rtl)"
    if sw_marker not in text:
        fail(f"could not find sw-sim fileset marker in {CORE_FILE}")
    text = text.replace(
        sw_marker,
        f"      - core_cvw ? (core_cvw_rtl)\n      - {flag} ? ({fileset})\n      - core_region ? (core_region_rtl)",
        1,
    )

    fpga_marker = "      - core_cvw ? (core_cvw_rtl)\n      - core_region ? (core_region_rtl)\n      - board_axku5 ? (board_axku5_rtl)"
    if fpga_marker not in text:
        fail(f"could not find fpga fileset marker in {CORE_FILE}")
    text = text.replace(
        fpga_marker,
        f"      - core_cvw ? (core_cvw_rtl)\n      - {flag} ? ({fileset})\n      - core_region ? (core_region_rtl)\n      - board_axku5 ? (board_axku5_rtl)",
        1,
    )

    path.write_text(text, encoding="utf-8")


def update_board_descriptor(repo_root: Path, args: argparse.Namespace) -> None:
    path = repo_root / "cfg" / "boards" / f"{args.board}.yaml"
    if not path.is_file():
        fail(f"board descriptor not found: {path.relative_to(repo_root)}")
    text = path.read_text(encoding="utf-8")
    path.write_text(append_yaml_top_list_item(text, "compatible_cores", args.core), encoding="utf-8")


def create_core(args: argparse.Namespace) -> None:
    repo_root = args.repo_root.resolve()
    require_identifier(args.core, "core")
    require_identifier(args.board, "board")
    require_identifier(args.integration_suffix, "integration suffix")
    if args.platform_integration != "socket_region":
        fail("the scaffold helper currently supports only socket_region cores")
    if args.instruction_bus not in {"obi", "axi", "ahb_lite", "serv_wishbone_minimal", "picorv32_native"}:
        fail(f"unsupported instruction bus contract: {args.instruction_bus}")
    if args.data_bus not in {"obi", "axi", "ahb_lite", "serv_wishbone_minimal", "picorv32_native"}:
        fail(f"unsupported data bus contract: {args.data_bus}")
    if args.xlen not in {32, 64}:
        fail("--xlen must be 32 or 64")
    if args.core_type is None:
        args.core_type = next_core_type(repo_root)
    if args.display_name is None:
        args.display_name = args.core.upper()
    if args.xlen == 32 and not args.mabi.startswith("ilp32"):
        fail("RV32 cores must use an ilp32 ABI")
    if args.xlen == 64 and not args.mabi.startswith("lp64"):
        fail("RV64 cores must use an lp64 ABI")
    if not args.march.startswith(f"rv{args.xlen}"):
        fail(f"--march must start with rv{args.xlen}")

    adapter = f"corejack_{args.core}_{args.integration_suffix}_adapter"
    files = {
        repo_root / "cfg" / "cores" / f"{args.core}.yaml": core_descriptor(args),
        repo_root / "rtl" / "cores" / f"{adapter}.sv": core_adapter(args),
        repo_root / f"corejack_core_{args.core}.core": core_fusesoc(args),
    }
    for path in files:
        if path.exists():
            fail(f"refusing to overwrite existing path: {path.relative_to(repo_root)}")

    update_platform_pkg(repo_root, args)
    update_corejack_core(repo_root, args)
    update_board_descriptor(repo_root, args)
    for path, content in files.items():
        write_new(path, content, repo_root)

    print(f"Created core scaffold for CORE={args.core}")
    print(f"Run: make core-check CORE={args.core}")
    print("Then replace the placeholder adapter with a real core integration.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", required=True, help="lowercase core name, e.g. mycore")
    parser.add_argument("--display-name", default=None, help="human-readable core name")
    parser.add_argument("--board", default="axku5", help="initial compatible board")
    parser.add_argument("--xlen", type=int, default=32)
    parser.add_argument("--march", default="rv32imc")
    parser.add_argument("--mabi", default="ilp32")
    parser.add_argument("--instruction-bus", default="obi")
    parser.add_argument("--data-bus", default="obi")
    parser.add_argument("--platform-integration", default="socket_region")
    parser.add_argument("--integration-suffix", default="socket")
    parser.add_argument("--core-type", type=int, default=None)
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    return parser.parse_args()


def main() -> None:
    create_core(parse_args())


if __name__ == "__main__":
    main()
