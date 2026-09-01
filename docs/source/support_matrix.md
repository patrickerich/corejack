# CoreJack Support Matrix

This page is generated from `cfg/cores/*.yaml` and `cfg/boards/*.yaml`.
Regenerate it with:

```bash
make support-matrix
```

Support status values come from core descriptors. `supported` means the
corresponding acceptance criteria have been validated for that flow.
`planned` means integration work is expected but not yet accepted.
`unsupported` means the flow is intentionally not claimed.

## Digilent Arty A7-100T (`arty_a7_100t`)

- FPGA part: `xc7a100tcsg324-1`
- SoC clock: `25000000` Hz
- UART baud: `115200`

| Core | Display name | Sim `hello_world` | FPGA `hello_world` | Load/run path | OpenOCD/GDB step | Default FPGA acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| `ibex` | Ibex | supported | supported | OpenOCD/GDB | supported | yes |
| `cv32e40p` | CV32E40P | supported | supported | OpenOCD/GDB | supported | yes |
| `cv32e40s` | CV32E40S | supported | supported | OpenOCD/GDB | supported | yes |
| `cva6` | CVA6 | supported | supported | OpenOCD/GDB | supported | yes |
| `serv` | SERV | supported | supported | UART loader | unsupported | yes |
| `picorv32` | PicoRV32 | supported | supported | UART loader | unsupported | yes |
| `cvw` | CORE-V-Wally | supported | supported | UART loader | unsupported | yes |

## ALINX AXKU5 (`axku5`)

- FPGA part: `xcku5p-ffvb676-2-e`
- SoC clock: `25000000` Hz
- UART baud: `115200`

| Core | Display name | Sim `hello_world` | FPGA `hello_world` | Load/run path | OpenOCD/GDB step | Default FPGA acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| `ibex` | Ibex | supported | supported | OpenOCD/GDB | supported | yes |
| `cv32e40p` | CV32E40P | supported | supported | OpenOCD/GDB | supported | yes |
| `cv32e40x` | CV32E40X | planned | unsupported | none | unsupported | no |
| `cv32e40s` | CV32E40S | supported | supported | OpenOCD/GDB | supported | yes |
| `cva6` | CVA6 | supported | supported | OpenOCD/GDB | supported | yes |
| `serv` | SERV | supported | supported | UART loader | unsupported | yes |
| `picorv32` | PicoRV32 | supported | supported | UART loader | unsupported | yes |
| `cvw` | CORE-V-Wally | supported | supported | UART loader | unsupported | yes |

## Core ISA Summary

| Core | Display name | XLEN | MARCH | MABI | Zephyr console/timer smoke | Compatible boards |
| --- | --- | --- | --- | --- | --- | --- |
| `cv32e40p` | CV32E40P | `rv32` | `rv32imc` | `ilp32` | initial_supported | `axku5`, `arty_a7_100t` |
| `cv32e40s` | CV32E40S | `rv32` | `rv32imc` | `ilp32` | initial_supported | `axku5`, `arty_a7_100t` |
| `cv32e40x` | CV32E40X | `rv32` | `rv32imc` | `ilp32` | unsupported | `axku5` |
| `cva6` | CVA6 | `rv64` | `rv64imc` | `lp64` | initial_supported | `axku5`, `arty_a7_100t` |
| `cvw` | CORE-V-Wally | `rv32` | `rv32imc` | `ilp32` | planned | `axku5`, `arty_a7_100t` |
| `ibex` | Ibex | `rv32` | `rv32imcb` | `ilp32` | initial_supported | `axku5`, `arty_a7_100t` |
| `picorv32` | PicoRV32 | `rv32` | `rv32imc` | `ilp32` | unsupported | `axku5`, `arty_a7_100t` |
| `serv` | SERV | `rv32` | `rv32i` | `ilp32` | initial_supported | `axku5`, `arty_a7_100t` |
