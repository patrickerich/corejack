zephyr_sources(
  ${ZEPHYR_BASE}/soc/common/riscv-privileged/soc_irq.S
  ${ZEPHYR_BASE}/soc/common/riscv-privileged/vector.S
)

zephyr_include_directories(.)

# CoreJack's iDMA driver, built when the app enables DMA and the devicetree has
# the iDMA (every board except SERV's).
if(CONFIG_DMA AND CONFIG_DT_HAS_COREJACK_IDMA_ENABLED)
  zephyr_sources(${CMAKE_CURRENT_LIST_DIR}/../../../drivers/dma/dma_corejack_idma.c)
endif()

set(SOC_LINKER_SCRIPT ${ZEPHYR_BASE}/include/zephyr/arch/riscv/common/linker.ld CACHE INTERNAL "")
