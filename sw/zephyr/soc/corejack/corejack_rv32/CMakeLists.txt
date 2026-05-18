zephyr_sources(
  ${ZEPHYR_BASE}/soc/common/riscv-privileged/soc_irq.S
  ${ZEPHYR_BASE}/soc/common/riscv-privileged/vector.S
)
zephyr_sources_ifdef(CONFIG_BOARD_COREJACK_SERV_AXKU5 spin_cpu_idle.c)

zephyr_include_directories(.)

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
