#!/usr/bin/env python3
"""Report host tool availability for CoreJack development flows."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

import validate_target


REPO_ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Tool:
    name: str
    command: str
    version_args: tuple[str, ...] = ("--version",)
    required_for: tuple[str, ...] = ("all",)
    search_paths: tuple[Path, ...] = ()
    note: str = ""
    expected_version: str = ""


def run_text(argv: list[str], timeout: float = 5.0) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            argv,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)

    output = result.stdout.strip().splitlines()
    first_line = output[0].strip() if output else ""
    return result.returncode == 0, first_line


def run_lines(argv: list[str], timeout: float = 5.0) -> tuple[bool, list[str]]:
    try:
        result = subprocess.run(
            argv,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, [str(exc)]

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return result.returncode == 0, lines


def find_command(command: str, extra_paths: tuple[Path, ...] = ()) -> str | None:
    for path in extra_paths:
        candidate = path / command
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return shutil.which(command)


def print_section(title: str) -> None:
    print()
    print(title)
    print("-" * len(title))


def flow_requires(tool: Tool, flow: str) -> bool:
    if flow == "all":
        return bool(tool.required_for)
    return "all" in tool.required_for or flow in tool.required_for


def toolchain_paths(toolchain: str) -> tuple[Path, str]:
    if toolchain == "riscv-multilib":
        root = Path(os.environ.get("COREJACK_RISCV_TOOLCHAIN", REPO_ROOT / ".tools" / "riscv"))
        return root, "riscv64-unknown-elf-"

    return Path(), "riscv64-unknown-elf-"


def check_tool(tool: Tool, flow: str) -> bool:
    required = flow_requires(tool, flow)
    exe = find_command(tool.command, tool.search_paths)
    status = "OK" if exe else ("MISSING" if required else "not found")
    marker = "!" if required and not exe else " "
    version_ok = True
    print(f"{marker} {tool.name:22} {status:8}", end="")

    if exe:
        ok, version = run_text([exe, *tool.version_args])
        detail = version if ok or version else exe
        if ok and tool.expected_version and tool.expected_version not in version:
            version_ok = False
            marker = "!" if required else " "
        print(f" {exe}")
        if detail:
            print(f"  {'':22} {detail}")
        if tool.expected_version:
            expected_status = "OK" if version_ok else "MISMATCH"
            print(f"{marker} {'expected':22} {expected_status:8} {tool.expected_version}")
    else:
        print()

    if tool.note:
        print(f"  {'':22} {tool.note}")

    return (bool(exe) and version_ok) or not required


def check_python_module(name: str, module: str, python: Path, required: bool) -> bool:
    exe = str(python)
    ok, version = run_text(
        [
            exe,
            "-c",
            f"import {module}; print(getattr({module}, '__version__', 'available'))",
        ]
    )
    status = "OK" if ok else ("MISSING" if required else "not found")
    marker = "!" if required and not ok else " "
    print(f"{marker} {name:22} {status:8} {module}")
    if ok and version:
        print(f"  {'':22} {version}")
    return ok or not required


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core", default="ibex", help="Selected core descriptor")
    parser.add_argument("--board", default="axku5", help="Selected board descriptor")
    parser.add_argument(
        "--flow",
        choices=("all", "sim", "fpga", "debug"),
        default="all",
        help="Tool group to check. Defaults to all.",
    )
    args = parser.parse_args()

    core_text, board_text = validate_target.load_descriptors(args.core, args.board)
    config = validate_target.target_config(args.core, args.board, core_text, board_text)
    toolchain_root, cross_prefix = toolchain_paths(config["TOOLCHAIN"])
    toolchain_bin = (toolchain_root / "bin",) if str(toolchain_root) else ()
    venv_bin = REPO_ROOT / ".venv" / "bin"
    bender_bin = REPO_ROOT / "bin" / ".tools"
    verilator_bin = Path(os.environ.get("COREJACK_VERILATOR", REPO_ROOT / ".tools" / "verilator")) / "bin"
    verible_bin = Path(os.environ.get("COREJACK_VERIBLE", REPO_ROOT / ".tools" / "verible")) / "bin"

    print(f"CoreJack tool check")
    print(f"  repo:      {REPO_ROOT}")
    print(f"  flow:      {args.flow}")
    print(f"  core:      {args.core}")
    print(f"  board:     {args.board}")
    print(f"  toolchain: {config['TOOLCHAIN']}")
    print(f"  march:     {config['MARCH']}")
    print(f"  mabi:      {config['MABI']}")
    if str(toolchain_root):
        print(f"  tc root:   {toolchain_root}")

    all_ok = True

    print_section("Core Tools")
    core_tools = [
        Tool("Python", sys.executable, ("--version",), ("all",)),
        Tool("venv Python", "python", ("--version",), ("all",), (venv_bin,)),
        Tool("GNU Make", "make", ("--version",), ("all",)),
        Tool("CMake", "cmake", ("--version",), ("all",)),
        Tool("Bender", "bender", ("--version",), ("all",), (bender_bin,)),
        Tool("FuseSoC", "fusesoc", ("--version",), ("all",), (venv_bin,)),
    ]
    for tool in core_tools:
        all_ok &= check_tool(tool, args.flow)

    print_section("Python Packages")
    venv_python = venv_bin / "python"
    py_required = args.flow in {"all", "sim", "fpga", "debug"}
    all_ok &= check_python_module("cocotb", "cocotb", venv_python, py_required)

    print_section("Firmware Toolchain")
    fw_tools = [
        Tool("C compiler", f"{cross_prefix}gcc", ("--version",), ("all",), toolchain_bin),
        Tool("objcopy", f"{cross_prefix}objcopy", ("--version",), ("all",), toolchain_bin),
        Tool("objdump", f"{cross_prefix}objdump", ("--version",), ("all",), toolchain_bin),
        Tool("readelf", f"{cross_prefix}readelf", ("--version",), ("all",), toolchain_bin),
        Tool("GDB", f"{cross_prefix}gdb", ("--version",), ("debug",), toolchain_bin),
    ]
    for tool in fw_tools:
        all_ok &= check_tool(tool, args.flow)

    gcc = find_command(f"{cross_prefix}gcc", toolchain_bin)
    if gcc:
        ok, multilib_lines = run_lines([gcc, "--print-multi-lib"])
        if ok:
            print(f"  {'multilib':22} {len(multilib_lines)} variants")
            for line in multilib_lines[:8]:
                print(f"  {'':22} {line}")
            if len(multilib_lines) > 8:
                print(f"  {'':22} ...")

    print_section("Simulation")
    sim_tools = [
        Tool("Verilator", "verilator", ("--version",), ("sim",), (verilator_bin,)),
    ]
    for tool in sim_tools:
        all_ok &= check_tool(tool, args.flow)

    if args.flow in {"all", "sim"}:
        print_section("Optional Verilator Build Prerequisites")
        verilator_build_tools = [
            Tool("git", "git", ("--version",), ()),
            Tool("autoconf", "autoconf", ("--version",), ()),
            Tool("flex", "flex", ("--version",), ()),
            Tool("bison", "bison", ("--version",), ()),
            Tool("help2man", "help2man", ("--version",), ()),
            Tool("Perl", "perl", ("--version",), ()),
            Tool("C++ compiler", os.environ.get("CXX", "g++"), ("--version",), ()),
        ]
        for tool in verilator_build_tools:
            check_tool(tool, args.flow)

        print(
            "  "
            + f"{'system packages':22} "
            + "zlib/flex runtime development headers may also be required by the host OS"
        )

    print_section("RTL Style")
    style_tools = [
        Tool("Verible lint", "verible-verilog-lint", ("--version",), (), (verible_bin,)),
        Tool("Verible format", "verible-verilog-format", ("--version",), (), (verible_bin,)),
        Tool("Verible syntax", "verible-verilog-syntax", ("--version",), (), (verible_bin,)),
    ]
    for tool in style_tools:
        check_tool(tool, args.flow)

    if args.flow in {"all", "sim"}:
        print_section("Optional Verible Binary Install Prerequisites")
        verible_install_tools = [
            Tool("curl", "curl", ("--version",), ()),
            Tool("tar", "tar", ("--version",), ()),
        ]
        for tool in verible_install_tools:
            check_tool(tool, args.flow)

    print_section("FPGA")
    fpga_tools = [
        Tool(
            "Vivado",
            "vivado",
            ("-version",),
            ("fpga",),
            expected_version=os.environ.get("COREJACK_VIVADO_VERSION", "2025.2.1"),
        ),
    ]
    for tool in fpga_tools:
        all_ok &= check_tool(tool, args.flow)

    print_section("Debug")
    debug_tools = [
        Tool("OpenOCD", "openocd", ("--version",), ("debug",)),
        Tool("picocom", "picocom", ("--help",), (), note="optional UART terminal"),
    ]
    for tool in debug_tools:
        all_ok &= check_tool(tool, args.flow)

    print()
    if all_ok:
        print("Result: OK")
        return 0

    print("Result: missing required tools")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
