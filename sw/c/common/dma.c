#include "dma.h"

static inline void mmio_write32(uintptr_t addr, uint32_t value) {
  *(volatile uint32_t *)addr = value;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
  return *(volatile uint32_t *)addr;
}

uint32_t dma_memcpy_start(uintptr_t dst, uintptr_t src, uint32_t len) {
  mmio_write32(DMA0_BASE + DMA_REG_DST_ADDR, (uint32_t)dst);
  mmio_write32(DMA0_BASE + DMA_REG_SRC_ADDR, (uint32_t)src);
  mmio_write32(DMA0_BASE + DMA_REG_LENGTH, len);
  /* CONF = 0: 1D transfer, AXI source and destination protocol. */
  mmio_write32(DMA0_BASE + DMA_REG_CONF, 0u);
  /* Reading NEXT_ID launches the transfer and returns its id. */
  return mmio_read32(DMA0_BASE + DMA_REG_NEXT_ID_0);
}

void dma_wait(uint32_t transfer_id) {
  /* DONE_ID holds the id of the most recently retired transfer; ids count
   * up from 1. The signed difference keeps the comparison correct across
   * the (theoretical) 32-bit wrap. */
  while ((int32_t)(mmio_read32(DMA0_BASE + DMA_REG_DONE_ID_0) - transfer_id) <
         0) {
  }
  /* The DMA wrote memory behind the core's back; force the compiler to
   * reload any buffered values. */
  __asm__ volatile("" ::: "memory");
}

void dma_memcpy(uintptr_t dst, uintptr_t src, uint32_t len) {
  dma_wait(dma_memcpy_start(dst, src, len));
}

uint32_t dma_irq_pending(void) {
  return mmio_read32(DMA0_BASE + DMA_REG_IRQ_STATUS) & 1u;
}

void dma_irq_ack(void) {
  mmio_write32(DMA0_BASE + DMA_REG_IRQ_STATUS, 1u);
}
