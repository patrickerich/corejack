set(COREJACK_CROSS_COMPILE "riscv32-unknown-elf-" CACHE STRING "RISC-V GNU toolchain executable prefix")

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_C_COMPILER ${COREJACK_CROSS_COMPILE}gcc)
set(CMAKE_ASM_COMPILER ${COREJACK_CROSS_COMPILE}gcc)
set(CMAKE_OBJCOPY ${COREJACK_CROSS_COMPILE}objcopy)
set(CMAKE_OBJDUMP ${COREJACK_CROSS_COMPILE}objdump)

set(COREJACK_MARCH "rv32imc" CACHE STRING "RISC-V -march value")
set(COREJACK_MABI "ilp32" CACHE STRING "RISC-V -mabi value")

set(CMAKE_C_FLAGS_INIT   "-Wall -fvisibility=hidden -ffreestanding")
set(CMAKE_ASM_FLAGS_INIT "")
# The linker script is generated per-board (board-driven RAM size) and applied
# per executable in CMakeLists.txt.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-nostartfiles -nostdlib -Wl,--gc-sections")
