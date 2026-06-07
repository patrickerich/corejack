# Board Porting Guide

This document describes the minimum pieces needed to add a new FPGA board to
CoreJack. A board port should keep board-specific logic in the board wrapper
and descriptor; core selection should continue to happen through `CORE=<core>`.

## Files

Add a board descriptor:

```text
cfg/boards/<board>.yaml
```

Add a board wrapper:

```text
rtl/platform/fpga/boards/<board>/corejack_<board>_wrap.sv
```

Add constraints:

```text
rtl/platform/fpga/boards/<board>/<board>.xdc
```

Add or reuse an OpenOCD configuration:

```text
rtl/platform/fpga/scripts/openocd.cfg
```

Add a board-local FuseSoC core at the repository root:

```text
corejack_board_<board>.core
```

That core should include the board wrapper and constraints. The shared
`corejack.core` `fpga` target should select the board core with a board flag,
for example `board_myboard ? (board_myboard_rtl)`, rather than duplicating a
new FPGA target for every board/core combination.

## Descriptor Template

Use this as the starting point for `cfg/boards/<board>.yaml`:

```yaml
name: myboard
display_name: My FPGA Board

fpga:
  part: xc...
  top_template: corejack_{board}_wrap
  target: fpga
  work_root: build/fpga/{board}/{core}/fusesoc-fpga

fusesoc:
  board_flag: board_myboard

clock:
  input_hz: 100000000
  soc_hz: 25000000
  constraints_ports:
    p: sys_clk_p
    n: sys_clk_n        # omit for a single-ended clock input

# Optional. Cap the shared SRAM for boards whose block RAM cannot hold the
# 1 MiB default; unset keeps the soc_top default. This is the single source of
# truth for the board's SRAM size: it is derived into the FPGA wrapper RamWords
# (soc_top RamWords vlogparam), the bare-metal linker, and the Zephyr
# devicetree (COREJACK_RAM_BYTES) - do not hardcode the size in those places.
# Example for a 256 KiB board:
# memory:
#   ram_bytes: 262144

reset:
  polarity: active_low
  constraints_port: sys_rst_n

uart:
  baud: 115200
  tx_port: uart_tx
  rx_port: uart_rx

debug:
  transport: jtag
  openocd_cfg: rtl/platform/fpga/scripts/openocd.cfg

constraints:
  xdc: rtl/platform/fpga/boards/myboard/myboard.xdc

programming:
  flow: vivado
  bitstream_target: fpga-bit
  program_target: fpga-pgm

validation:
  smoke_app: hello_world
  expected_uart:
    - "=== CoreJack SoC Demo ==="
    - "Target: fpga"
    - "Core: {core}"
    - "Board: {board}"
    - "path is alive."

compatible_cores:
  - ibex
```

For each core that should build on the board, also add the board name to that
core descriptor's `compatible_boards` list.

## FuseSoC Board Core

Use this shape for `corejack_board_<board>.core`:

```yaml
CAPI=2:

name: corejack:boards:myboard:0.1.0
description: My FPGA board wrapper and constraints for CoreJack

filesets:
  board_rtl:
    files:
      - rtl/platform/fpga/boards/myboard/corejack_myboard_wrap.sv
      - rtl/platform/fpga/boards/myboard/myboard.xdc : {file_type: xdc}
    file_type: systemVerilogSource

targets:
  default:
    filesets:
      - board_rtl
```

Then add one board-selection fileset to `corejack.core`:

```yaml
board_myboard_rtl:
  depend:
    - corejack:boards:myboard:0.1.0
```

The shared `fpga` target should conditionally select board-specific files,
top-level, and Vivado part:

```yaml
flow_options:
  part: board_myboard ? (xc...)
filesets_append:
  - board_myboard ? (board_myboard_rtl)
toplevel: board_myboard ? (corejack_myboard_wrap)
```

For multiple boards, extend these conditional expressions instead of adding
per-board FPGA targets.

## Add-A-Board Checklist

The scaffold helper creates the descriptor, wrapper, XDC, board FuseSoC core,
and the minimal shared `corejack.core` board-selection hooks:

```bash
make new-board BOARD=myboard FPGA_PART=xc...
```

Optionally set `BOARD_DISPLAY_NAME="My Board"`. The scaffold intentionally
uses placeholder XDC pins and conservative wrapper clocking; review both before
attempting bitstream generation.

Manual checklist:

1. Add `cfg/boards/<board>.yaml` with `fpga.target: fpga`,
   `fpga.work_root: build/fpga/{board}/{core}/fusesoc-fpga`, and a unique
   `fusesoc.board_flag`.
2. Add `rtl/platform/fpga/boards/<board>/corejack_<board>_wrap.sv`.
3. Add `rtl/platform/fpga/boards/<board>/<board>.xdc`.
4. Add `corejack_board_<board>.core`.
5. Add the board fileset dependency and board-flag conditionals to the shared
   `fpga` target in `corejack.core`.
6. Add the board name to each compatible core descriptor.
7. Run `make board-check BOARD=<board>` and
   `make target-check BOARD=<board>`.
8. Validate at least one supported core on hardware before promoting support.

## Board Wrapper Checklist

The board wrapper should provide only board-specific adaptation:

- FPGA clock input buffers and clock generation
- reset synchronization and board reset polarity handling
- UART pin wiring
- JTAG/debug pin wiring or connection to the debug transport used by OpenOCD
- instantiation of the generic CoreJack SoC top
- pass-through of the `CoreType` parameter into the generic SoC

The wrapper should not encode a fixed core choice in the top-level module name.
Core selection is descriptor-driven through `CORE=<core>`.

## Constraints Checklist

The XDC should define:

- clock input pins and I/O standards
- reset pin and I/O standard
- UART TX/RX pins and I/O standards
- any board-specific clock constraints not generated by the wrapper

Keep board-local generated Vivado project files out of version control.

## Validation

Check the descriptor and referenced local files:

```bash
make board-check BOARD=<board>
```

Check the board/core descriptor matrix:

```bash
make target-check BOARD=<board>
```

The checker validates:

- required descriptor fields
- FPGA wrapper file and top module name
- XDC path
- OpenOCD config path
- FuseSoC target name
- FuseSoC board flag
- Make programming targets
- clock, UART, reset, debug, and programming sanity
- compatible core names and reciprocal core compatibility
- isolated `{board}` and `{core}` placeholders in `fpga.work_root`

The board target normally names the shared generic `fpga` FuseSoC target. Board
source selection is supplied separately through `fusesoc.board_flag`; selected
core source selection comes from the core descriptor's `fusesoc.core_flag` plus
any descriptor-derived integration flags. A new board should add a board-local
`.core` file and board flag, not duplicate every core selection in another FPGA
target.

Use `{core}` and `{board}` placeholders in board-level expected UART fragments
when the expected text is core- or board-specific. This keeps the board
descriptor reusable across all compatible cores.

After the descriptor check passes, run the usual FPGA flow:

```bash
source sourceme.sh
make deps
make fpga-bit BOARD=<board> CORE=ibex
make fpga-pgm BOARD=<board> CORE=ibex
make openocd BOARD=<board> CORE=ibex
make fpga-run-sw BOARD=<board> CORE=ibex SW_APP=hello_world GDB_TIMEOUT=10
```

For a board-level acceptance sweep:

```bash
make fpga-accept BOARD=<board> UART_DEV=/dev/serial/by-id/<uart-device>
```

Promote a board/core combination only after bitstream generation, programming,
OpenOCD/GDB load/run, and UART output have all been validated on hardware.
