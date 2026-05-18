#!/usr/bin/env python3
"""Create a conservative CoreJack FPGA board scaffold."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_FILE = "corejack.core"


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def require_identifier(name: str, field: str) -> None:
    if not re.fullmatch(r"[a-z][a-z0-9_]*", name):
        fail(f"{field} must match [a-z][a-z0-9_]*, got '{name}'")


def write_new(path: Path, content: str, repo_root: Path) -> None:
    if path.exists():
        fail(f"refusing to overwrite existing path: {path.relative_to(repo_root)}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def board_descriptor(args: argparse.Namespace) -> str:
    return f"""name: {args.board}
display_name: {args.display_name}

fpga:
  part: {args.part}
  top_template: corejack_{{board}}_wrap
  target: fpga
  work_root: build/fpga/{{board}}/{{core}}/fusesoc-fpga

fusesoc:
  board_flag: board_{args.board}

clock:
  input_hz: {args.input_hz}
  soc_hz: {args.soc_hz}
  constraints_ports:
    p: {args.clock_p}
    n: {args.clock_n}

reset:
  polarity: {args.reset_polarity}
  constraints_port: {args.reset_port}

uart:
  baud: {args.uart_baud}
  tx_port: {args.uart_tx}
  rx_port: {args.uart_rx}

debug:
  transport: jtag
  openocd_cfg: rtl/platform/fpga/scripts/openocd.cfg

constraints:
  xdc: rtl/platform/fpga/boards/{args.board}/{args.board}.xdc

programming:
  flow: vivado
  bitstream_target: fpga-bit
  program_target: fpga-pgm

validation:
  smoke_app: hello_world
  expected_uart:
    - "=== CoreJack SoC Demo ==="
    - "Target: fpga"
    - "Core: {{core}}"
    - "Board: {{board}}"
    - "path is alive."

compatible_cores:
  - ibex
"""


def board_core(args: argparse.Namespace) -> str:
    return f"""CAPI=2:

name: corejack:boards:{args.board}:0.1.0
description: {args.display_name} FPGA board wrapper and constraints for CoreJack

filesets:
  board_rtl:
    files:
      - rtl/platform/fpga/boards/{args.board}/corejack_{args.board}_wrap.sv
      - rtl/platform/fpga/boards/{args.board}/{args.board}.xdc : {{file_type: xdc}}
    file_type: systemVerilogSource

targets:
  default:
    filesets:
      - board_rtl
"""


def board_xdc(args: argparse.Namespace) -> str:
    return f"""# {args.display_name} constraints for CoreJack.
# Replace the PACKAGE_PIN placeholders with board-specific pin names before
# attempting bitstream generation.

# Differential input clock
# set_property PACKAGE_PIN <CLK_P_PIN> [get_ports {{{args.clock_p}}}]
# set_property PACKAGE_PIN <CLK_N_PIN> [get_ports {{{args.clock_n}}}]
# set_property IOSTANDARD DIFF_SSTL12 [get_ports {{{args.clock_p} {args.clock_n}}}]
# create_clock -period 10.000 [get_ports {{{args.clock_p}}}]

# Reset
# set_property PACKAGE_PIN <RESET_PIN> [get_ports {{{args.reset_port}}}]
# set_property IOSTANDARD LVCMOS18 [get_ports {{{args.reset_port}}}]

# UART
# set_property PACKAGE_PIN <UART_TX_PIN> [get_ports {{{args.uart_tx}}}]
# set_property PACKAGE_PIN <UART_RX_PIN> [get_ports {{{args.uart_rx}}}]
# set_property IOSTANDARD LVCMOS18 [get_ports {{{args.uart_tx} {args.uart_rx}}}]

# JTAG/debug pins, LEDs, and any other board-specific I/O belong here.
"""


def board_wrapper(args: argparse.Namespace) -> str:
    module = f"corejack_{args.board}_wrap"
    return f"""module {module} #(
  parameter int unsigned CoreType = platform_pkg::CORE_IBEX,
  parameter bit EnableUartLoader = 1'b0
) (
  input  logic       {args.clock_p},
  input  logic       {args.clock_n},
  input  logic       {args.reset_port},
  output logic [3:0] led,
  output logic       {args.uart_tx},
  input  logic       {args.uart_rx},
  input  logic       jtag_tck,
  input  logic       jtag_tms,
  input  logic       jtag_trst_n,
  input  logic       jtag_tdi,
  output logic       jtag_tdo
);
  import dm::*;
  import soc_bus_pkg::*;

  logic clk_in;
  logic clk_in_buf;
  logic core_clk_raw;
  logic core_clk;
  logic pll_clkfb;
  logic pll_locked;
  logic pll_locked_r;
  logic rst_ni_raw;
  logic dmactive;
  logic debug_req;
  logic alert_minor;
  logic alert_major_internal;
  logic alert_major_bus;
  logic core_sleep;
  soc_apb_req_t apb_req_unused;
  soc_apb_resp_t apb_rsp_unused;

  IBUFDS i_sys_clk_ibufds (
    .I ({args.clock_p}),
    .IB({args.clock_n}),
    .O (clk_in)
  );

  BUFG i_sys_clk_bufg (
    .I(clk_in),
    .O(clk_in_buf)
  );

  // TODO: Adjust PLL parameters for the board input clock and target SoC clock.
  PLLE2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKFBOUT_MULT(5),
    .CLKIN1_PERIOD(10.0),
    .CLKOUT0_DIVIDE(20),
    .DIVCLK_DIVIDE(1),
    .STARTUP_WAIT("FALSE")
  ) i_pll (
    .CLKOUT0(core_clk_raw),
    .CLKOUT1(),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKFBOUT(pll_clkfb),
    .LOCKED(pll_locked),
    .CLKIN1(clk_in_buf),
    .PWRDWN(1'b0),
    .RST(1'b0),
    .CLKFBIN(pll_clkfb)
  );

  BUFG i_core_clk_bufg (
    .I(core_clk_raw),
    .O(core_clk)
  );

  always_ff @(posedge core_clk or negedge {args.reset_port}) begin
    if (!{args.reset_port}) begin
      pll_locked_r <= 1'b0;
      rst_ni_raw   <= 1'b0;
    end else begin
      pll_locked_r <= pll_locked;
      rst_ni_raw   <= pll_locked_r;
    end
  end

  assign apb_req_unused = '0;

  soc_top #(
    .apb_req_t       (soc_apb_req_t),
    .apb_rsp_t       (soc_apb_resp_t),
    .axi_req_t       (soc_axi_req_t),
    .axi_rsp_t       (soc_axi_resp_t),
    .obi_req_t       (soc_obi_req_t),
    .obi_rsp_t       (soc_obi_rsp_t),
    .CoreType        (CoreType),
    .EnablePlatform  (1'b1),
    .EnableUartLoader(EnableUartLoader),
    .MemImpl         (mem_ss_pkg::MemImplXilinx)
  ) i_soc_top (
    .clk_i                  (core_clk),
    .rst_ni                 (rst_ni_raw),
    .apb_req_i              (apb_req_unused),
    .apb_rsp_o              (apb_rsp_unused),
    .uart_rx_i              ({args.uart_rx}),
    .uart_tx_o              ({args.uart_tx}),
    .jtag_tck_i             (jtag_tck),
    .jtag_tms_i             (jtag_tms),
    .jtag_trst_ni           (jtag_trst_n),
    .jtag_tdi_i             (jtag_tdi),
    .jtag_tdo_o             (jtag_tdo),
    .dmactive_o             (dmactive),
    .debug_req_o            (debug_req),
    .alert_minor_o          (alert_minor),
    .alert_major_internal_o (alert_major_internal),
    .alert_major_bus_o      (alert_major_bus),
    .core_sleep_o           (core_sleep)
  );

  assign led = {{core_sleep, debug_req, dmactive, rst_ni_raw}};
endmodule
"""


def replace_in_fpga_target(text: str, args: argparse.Namespace) -> str:
    flag = f"board_{args.board}"
    fileset = f"{flag}_rtl"
    top = f"corejack_{args.board}_wrap"

    if f"  {fileset}:" in text:
        fail(f"{fileset} already exists in {CORE_FILE}")
    if f"{flag} ? (" in text:
        fail(f"{flag} already exists in {CORE_FILE}")

    rtl_marker = "\n  rtl:\n"
    fileset_block = f"""
  {fileset}:
    depend:
      - corejack:boards:{args.board}:0.1.0
"""
    if rtl_marker not in text:
        fail(f"could not find rtl fileset marker in {CORE_FILE}")
    text = text.replace(rtl_marker, fileset_block + rtl_marker, 1)

    lines = text.splitlines()
    in_fpga = False
    in_flow_options = False
    changed_part = False
    changed_filesets = False
    changed_top = False
    out: list[str] = []

    for line in lines:
        if line == "  fpga:":
            in_fpga = True
        elif in_fpga and re.match(r"^  [A-Za-z0-9_-]+:", line) and line != "  fpga:":
            in_fpga = False
            in_flow_options = False

        if in_fpga and line == "    flow_options:":
            in_flow_options = True
        elif in_fpga and in_flow_options and re.match(r"^    [A-Za-z0-9_-]+:", line) and line != "    flow_options:":
            in_flow_options = False

        if in_fpga and in_flow_options and line.startswith("      part: "):
            line = f"{line} {flag} ? ({args.part})"
            changed_part = True

        if in_fpga and line.startswith("    toplevel: "):
            if not changed_filesets:
                out.append(f"      - {flag} ? ({fileset})")
                changed_filesets = True
            line = f"{line} {flag} ? ({top})"
            changed_top = True

        out.append(line)

    if not changed_part:
        fail(f"could not update fpga flow_options.part in {CORE_FILE}")
    if not changed_filesets:
        fail(f"could not update fpga filesets_append in {CORE_FILE}")
    if not changed_top:
        fail(f"could not update fpga toplevel in {CORE_FILE}")

    return "\n".join(out) + "\n"


def update_corejack_core(repo_root: Path, args: argparse.Namespace) -> None:
    core_path = repo_root / CORE_FILE
    text = core_path.read_text(encoding="utf-8")
    updated = replace_in_fpga_target(text, args)
    core_path.write_text(updated, encoding="utf-8")


def create_board(args: argparse.Namespace) -> None:
    repo_root = args.repo_root.resolve()

    require_identifier(args.board, "board")
    if args.reset_polarity not in {"active_low"}:
        fail("only active_low reset scaffolds are currently supported")

    files = {
        repo_root / "cfg" / "boards" / f"{args.board}.yaml": board_descriptor(args),
        repo_root / "rtl" / "platform" / "fpga" / "boards" / args.board / f"{args.board}.xdc": board_xdc(args),
        repo_root / "rtl" / "platform" / "fpga" / "boards" / args.board / f"corejack_{args.board}_wrap.sv": board_wrapper(args),
        repo_root / f"corejack_board_{args.board}.core": board_core(args),
    }

    for path in files:
        if path.exists():
            fail(f"refusing to overwrite existing path: {path.relative_to(repo_root)}")

    update_corejack_core(repo_root, args)
    for path, content in files.items():
        write_new(path, content, repo_root)

    print(f"Created board scaffold for BOARD={args.board}")
    print(f"Run: make board-check BOARD={args.board}")
    print(f"Then review the wrapper PLL settings and fill in the XDC pin constraints.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--board", required=True, help="lowercase board name, e.g. myboard")
    parser.add_argument("--part", required=True, help="Vivado FPGA part name")
    parser.add_argument("--display-name", default=None, help="human-readable board name")
    parser.add_argument("--input-hz", type=int, default=100_000_000)
    parser.add_argument("--soc-hz", type=int, default=25_000_000)
    parser.add_argument("--clock-p", default="sys_clk_p")
    parser.add_argument("--clock-n", default="sys_clk_n")
    parser.add_argument("--reset-port", default="sys_rst_n")
    parser.add_argument("--reset-polarity", default="active_low")
    parser.add_argument("--uart-baud", type=int, default=115_200)
    parser.add_argument("--uart-tx", default="uart_tx")
    parser.add_argument("--uart-rx", default="uart_rx")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args = parser.parse_args()
    if args.display_name is None:
        args.display_name = args.board.upper()
    return args


def main() -> None:
    create_board(parse_args())


if __name__ == "__main__":
    main()
