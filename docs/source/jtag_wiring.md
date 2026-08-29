# External JTAG Wiring — AXKU5 (Tigard) / Arty A7-100T (Olimex)

External-JTAG lead assignments for the `riscv-dbg` soft TAP, per board. Each
board selects its JTAG adapter through `debug.jtag_adapter` in
`cfg/boards/<board>.yaml`:

- **AXKU5**: Tigard v1 — `rtl/platform/fpga/scripts/openocd-tigard.cfg`
- **Arty A7-100T**: Olimex ARM-USB-TINY (15ba:0004) —
  `rtl/platform/fpga/scripts/openocd-olimex-arm-usb-tiny.cfg`

Both wrappers share the same riscv-dbg target setup
(`openocd-riscv-target.cfg`, IDCODE `0x1`), so both boards can stay connected
simultaneously; OpenOCD picks the right probe by adapter type, and Vivado
programming picks the right board by FPGA part. The FPGA-side pin tables below
apply regardless of which probe is soldered to the header.

## Using A Different Or Custom JTAG Adapter

The adapter choice is just a name resolving to
`rtl/platform/fpga/scripts/openocd-<name>.cfg`:

- **Per board (persistent)**: set `debug.jtag_adapter: <name>` in
  `cfg/boards/<board>.yaml`. This is the project default for that board and
  is validated by `make board-check`.
- **Per invocation (your bench differs)**: pass `JTAG_ADAPTER=<name>` to any
  make target that talks to OpenOCD (`make openocd`, `make fpga-accept`, the
  acceptance script honours the same variable), without editing tracked
  files. A fully custom config file can also be passed directly with
  `OPENOCD_CFG=<path>`.
- **Adding a new adapter**: create a three-line wrapper next to the existing
  ones. For example, for an Olimex ARM-USB-TINY-H (`15ba:002a`):

  ```tcl
  # rtl/platform/fpga/scripts/openocd-olimex-arm-usb-tiny-h.cfg
  source [find interface/ftdi/olimex-arm-usb-tiny-h.cfg]
  transport select jtag
  source [file join [file dirname [info script]] openocd-riscv-target.cfg]
  ```

  Any probe with an upstream OpenOCD `interface/` config works the same way;
  the shared `openocd-riscv-target.cfg` provides the riscv-dbg TAP setup and
  must not be duplicated into adapter wrappers.

| Signal (port) | AXKU5 FPGA pin | AXKU5 `J8` pin | Arty FPGA pin | Arty `JD` (Pmod) pin |
| --- | --- | --- | --- | --- |
| `jtag_tck`    | A13 | 34 | D4 | JD1 |
| `jtag_tms`    | G12 | 32 | D3 | JD2 |
| `jtag_tdi`    | E13 | 30 | F3 | JD4 |
| `jtag_tdo`    | D14 | 36 | F4 | JD3 |
| `jtag_trst_n` | C12 | 28 | E2 | JD7 |
| `GND`         | —   | 37 / 38 (or 1) | — | JD5 / JD11 |
| `VTGT` (3.3 V)| —   | 39 / 40 | — | JD6 / JD12 |

Both boards: `IOSTANDARD LVCMOS33`; `PULLTYPE PULLUP` on `jtag_tms` and
`jtag_trst_n`. `jtag_tdi`/`jtag_tdo` direction is from the SoC: `tdi` = Tigard →
FPGA, `tdo` = FPGA → Tigard.

## AXKU5 — connector J8 (40-pin, 2.54 mm expansion port)
Two columns: odd pins (1,3,…) on one side, even (2,4,…) on the other. Pin 1 =
GND, pin 2 = +5V, pins 37/38 = GND, pins 39/40 = +3.3V. All five JTAG signals
sit on the **even-pin column** (28–36); FPGA-side net names IO1_13P(28),
IO1_14P(30), IO1_15P(32), IO1_16P(34), IO1_17P(36). The board has only one
bank of these IO pins, so the mapping is unambiguous.

## Arty A7-100T — connector JD (2×6 Pmod)
Top row pin1–4 = JD1/JD2/JD3/JD4, pin5 = GND, pin6 = 3V3; bottom row pin7 = JD7,
pin8–10 = JD8/JD9/JD10, pin11 = GND, pin12 = 3V3.

Identifying JD pin 1 (no numbers are printed on the Arty PCB):
- **Square pad = pin 1.** Flip the board over: the pin-1 pad is square; all
  others are round. (Standard PCB convention.)
- **Orient by the silkscreen `GND`/`VCC` labels** Digilent prints at one end of
  each Pmod — those are pins 5/6 (top row) and 11/12 (bottom row). Pin 1 and
  pin 7 are at the opposite end.
- **Confirm with a multimeter** before wiring: the VCC pins read 3.3 V to the
  GND pins; this locks the orientation independent of any marking.

## Sources
- AXKU5: `AXKU5_1.1_User_Manual.pdf` Part 3.8 (connector J8) cross-referenced
  with `rtl/platform/fpga/boards/axku5/axku5.xdc` (FPGA balls).
- Arty: `rtl/platform/fpga/boards/arty_a7_100t/arty_a7_100t.xdc`.

> Verify against the actual board before trusting: the wires/pads in front of
> you are the ground truth, not this table.
