#!/usr/bin/env python3
"""Render descriptor-derived CoreJack support matrices."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_DIR = REPO_ROOT / "cfg" / "cores"
BOARD_DIR = REPO_ROOT / "cfg" / "boards"
OUT_PATH = REPO_ROOT / "docs" / "source" / "support_matrix.md"


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def yaml_path_scalar(text: str, path: tuple[str, ...]) -> str | None:
    current_path: list[tuple[int, str]] = []

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("- "):
            continue

        match = re.match(r"^(\s*)([A-Za-z0-9_]+):\s*(.*?)\s*$", line)
        if not match:
            continue

        indent = len(match.group(1))
        key = match.group(2)
        value = match.group(3)

        while current_path and current_path[-1][0] >= indent:
            current_path.pop()
        current_path.append((indent, key))

        if tuple(item[1] for item in current_path) == path:
            if not value:
                return None
            return value.strip().strip("'\"")

    return None


def require_scalar(text: str, path: tuple[str, ...], descriptor: Path) -> str:
    value = yaml_path_scalar(text, path)
    if value is None:
        raise SystemExit(f"missing {'.'.join(path)} in {descriptor.relative_to(REPO_ROOT)}")
    return value


def yaml_top_list(text: str, key: str) -> list[str]:
    lines = text.splitlines()
    values: list[str] = []
    in_list = False
    base_indent = 0

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        key_match = re.match(rf"^(\s*){re.escape(key)}:\s*(.*)$", line)
        if key_match:
            in_list = True
            base_indent = len(key_match.group(1))
            inline = key_match.group(2).strip()
            if inline.startswith("[") and inline.endswith("]"):
                body = inline[1:-1].strip()
                if body:
                    values.extend(item.strip().strip("'\"") for item in body.split(","))
                return values
            if inline:
                values.append(inline.strip("'\""))
                return values
            continue

        if in_list:
            indent = len(line) - len(line.lstrip())
            if indent <= base_indent:
                break
            item_match = re.match(r"^\s*-\s*(.+?)\s*$", line)
            if item_match:
                values.append(item_match.group(1).strip().strip("'\""))

    return values


def descriptor_names(directory: Path) -> list[str]:
    return sorted(path.stem for path in directory.glob("*.yaml"))


def core_record(core: str) -> dict[str, str | list[str]]:
    path = CORE_DIR / f"{core}.yaml"
    text = path.read_text(encoding="utf-8")
    return {
        "name": core,
        "display": require_scalar(text, ("display_name",), path),
        "xlen": require_scalar(text, ("isa", "xlen"), path),
        "march": require_scalar(text, ("isa", "march"), path),
        "mabi": require_scalar(text, ("isa", "mabi"), path),
        "sim": require_scalar(text, ("integration", "sim"), path),
        "fpga": require_scalar(text, ("integration", "fpga"), path),
        "debug": require_scalar(text, ("integration", "debug"), path),
        "zephyr": yaml_path_scalar(text, ("software", "zephyr", "status")) or "planned",
        "debug_supported": require_scalar(text, ("debug", "supported"), path),
        "compatible_boards": yaml_top_list(text, "compatible_boards"),
    }


def board_record(board: str) -> dict[str, str | list[str]]:
    path = BOARD_DIR / f"{board}.yaml"
    text = path.read_text(encoding="utf-8")
    return {
        "name": board,
        "display": require_scalar(text, ("display_name",), path),
        "part": require_scalar(text, ("fpga", "part"), path),
        "soc_hz": require_scalar(text, ("clock", "soc_hz"), path),
        "uart_baud": require_scalar(text, ("uart", "baud"), path),
        "compatible_cores": yaml_top_list(text, "compatible_cores"),
    }


def load_run_path(core: dict[str, str | list[str]]) -> str:
    debug_status = str(core["debug"])
    if debug_status == "supported":
        return "OpenOCD/GDB"
    if str(core["fpga"]) == "supported":
        return "UART loader"
    return "none"


def default_fpga_acceptance(core: dict[str, str | list[str]]) -> str:
    return "yes" if str(core["fpga"]) == "supported" else "no"


def table(headers: list[str], rows: list[list[str]]) -> str:
    out = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    out.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(out)


def render_board_matrix(board: dict[str, str | list[str]], cores: dict[str, dict[str, str | list[str]]]) -> str:
    board_name = str(board["name"])
    rows: list[list[str]] = []
    for core_name in board["compatible_cores"]:
        core = cores[str(core_name)]
        rows.append(
            [
                f"`{core_name}`",
                str(core["display"]),
                str(core["sim"]),
                str(core["fpga"]),
                load_run_path(core),
                str(core["debug"]),
                default_fpga_acceptance(core),
            ]
        )

    lines = [
        f"## {board['display']} (`{board_name}`)",
        "",
        f"- FPGA part: `{board['part']}`",
        f"- SoC clock: `{board['soc_hz']}` Hz",
        f"- UART baud: `{board['uart_baud']}`",
        "",
        table(
            [
                "Core",
                "Display name",
                "Sim `hello_world`",
                "FPGA `hello_world`",
                "Load/run path",
                "OpenOCD/GDB step",
                "Default FPGA acceptance",
            ],
            rows,
        ),
    ]
    return "\n".join(lines)


def render_core_matrix(cores: dict[str, dict[str, str | list[str]]]) -> str:
    rows = [
        [
            f"`{name}`",
            str(core["display"]),
            f"`rv{core['xlen']}`",
            f"`{core['march']}`",
            f"`{core['mabi']}`",
            str(core["zephyr"]),
            ", ".join(f"`{board}`" for board in core["compatible_boards"]),
        ]
        for name, core in cores.items()
    ]
    return table(
        ["Core", "Display name", "XLEN", "MARCH", "MABI", "Zephyr console/timer smoke", "Compatible boards"],
        rows,
    )


def render() -> str:
    cores = {name: core_record(name) for name in descriptor_names(CORE_DIR)}
    boards = {name: board_record(name) for name in descriptor_names(BOARD_DIR)}

    lines = [
        "# CoreJack Support Matrix",
        "",
        "This file is generated from `cfg/cores/*.yaml` and `cfg/boards/*.yaml`.",
        "Regenerate it with:",
        "",
        "```bash",
        "make support-matrix",
        "```",
        "",
        "Support status values come from core descriptors. `supported` means the",
        "corresponding acceptance criteria have been validated for that flow.",
        "`planned` means integration work is expected but not yet accepted.",
        "`unsupported` means the flow is intentionally not claimed.",
        "",
    ]

    for board_name in boards:
        lines.append(render_board_matrix(boards[board_name], cores))
        lines.append("")

    lines.extend(["## Core ISA Summary", "", render_core_matrix(cores), ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if docs/source/support_matrix.md is stale")
    parser.add_argument("--out", type=Path, default=OUT_PATH)
    args = parser.parse_args()

    rendered = render()
    if args.check:
        existing = args.out.read_text(encoding="utf-8") if args.out.is_file() else ""
        if existing != rendered:
            raise SystemExit(f"{display_path(args.out)} is stale; run make support-matrix")
        return

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(rendered, encoding="utf-8")
    print(f"Wrote {display_path(args.out)}")


if __name__ == "__main__":
    main()
