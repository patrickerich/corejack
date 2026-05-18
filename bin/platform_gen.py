#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import yaml


def _to_int(value: int | str) -> int:
    if isinstance(value, int):
        return value
    return int(str(value), 0)


def _render_addr_map(platform: dict) -> str:
    lines = [
        "package addr_map_pkg;",
        "",
    ]
    for periph in platform.get("peripherals", []):
        name = periph["name"].upper()
        base = _to_int(periph["base"])
        size = _to_int(periph["size"])
        lines.append(f"  localparam logic [31:0] {name}_BASE = 32'h{base:08X};")
        lines.append(f"  localparam logic [31:0] {name}_SIZE = 32'h{size:08X};")

    for sl in platform.get("memory", {}).get("slices", []):
        name = sl["name"].upper()
        base = _to_int(sl["base"])
        size = _to_int(sl["size"])
        lines.append(f"  localparam logic [31:0] {name}_BASE = 32'h{base:08X};")
        lines.append(f"  localparam logic [31:0] {name}_SIZE = 32'h{size:08X};")

    lines += ["", "endpackage", ""]
    return "\n".join(lines)


def _render_top(platform: dict) -> str:
    name = platform.get("name", "corejack_soc")
    ic_type = platform.get("interconnect", {}).get("type", "axi_hierarchical")
    map_mode = platform.get("memory", {}).get("map_mode", "interleaved")
    gran = platform.get("memory", {}).get("interleave_granularity", 64)
    slices = platform.get("memory", {}).get("slices", [])

    lines = [
        f"module soc_top_gen_{name} ();",
        f"  localparam string INTERCONNECT = \"{ic_type}\";",
        f"  localparam string MEM_MAP_MODE = \"{map_mode}\";",
        f"  localparam int unsigned INTERLEAVE_GRANULARITY = {int(gran)};",
        f"  localparam int unsigned N_MEM_SLICES = {len(slices)};",
        "",
        "  // Generated integration placeholder.",
        "  // Instantiate platform modules and pass these params in your hand-authored top.",
    ]

    for idx, sl in enumerate(slices):
        lines.append(
            f"  localparam logic [31:0] MEM_SLICE_{idx}_BASE = 32'h{_to_int(sl['base']):08X};"
        )
        lines.append(
            f"  localparam logic [31:0] MEM_SLICE_{idx}_SIZE = 32'h{_to_int(sl['size']):08X};"
        )
        lines.append(f"  localparam string MEM_SLICE_{idx}_TECH = \"{sl['tech']}\";")

    lines += ["", "endmodule", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate CoreJack platform glue files.")
    parser.add_argument("--config", required=True, help="Path to platform YAML config")
    parser.add_argument("--out", required=True, help="Output directory for generated files")
    args = parser.parse_args()

    cfg_path = Path(args.config)
    out_dir = Path(args.out)
    rtl_out_dir = out_dir / "rtl"
    rtl_out_dir.mkdir(parents=True, exist_ok=True)

    with cfg_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f)

    platform = cfg.get("platform", {})
    (rtl_out_dir / "addr_map_pkg.sv").write_text(_render_addr_map(platform), encoding="utf-8")
    (rtl_out_dir / "soc_top_gen.sv").write_text(_render_top(platform), encoding="utf-8")


if __name__ == "__main__":
    main()
