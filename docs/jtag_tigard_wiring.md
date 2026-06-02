# Tigard JTAG Wiring — AXKU5 ⇄ Arty A7-100T

External-JTAG (Tigard) lead assignments for the `riscv-dbg` soft TAP, per board.
Use this when moving the Tigard between boards. The OpenOCD config
(`rtl/platform/fpga/scripts/openocd.cfg`, Tigard + `riscv-dbg`, IDCODE `0x1`) is
shared; only the physical pins and `BOARD=` differ.

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
