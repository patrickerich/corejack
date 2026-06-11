#include "plic.h"

/* Standard RISC-V PLIC layout (single M-mode context, context 0). */
#define PLIC_PRIORITY(src) (PLIC0_BASE + 4u * (src))
#define PLIC_ENABLE(src)   (PLIC0_BASE + 0x2000u + 4u * ((src) / 32u))
#define PLIC_THRESHOLD     (PLIC0_BASE + 0x200000u)
#define PLIC_CLAIM         (PLIC0_BASE + 0x200004u)

static inline uint32_t mmio_read32(uint32_t addr) {
  return *(volatile uint32_t *)(uintptr_t)addr;
}

static inline void mmio_write32(uint32_t addr, uint32_t value) {
  *(volatile uint32_t *)(uintptr_t)addr = value;
}

void plic_set_priority(uint32_t src, uint32_t prio) {
  mmio_write32(PLIC_PRIORITY(src), prio);
}

void plic_enable(uint32_t src) {
  uint32_t enable = mmio_read32(PLIC_ENABLE(src));
  mmio_write32(PLIC_ENABLE(src), enable | (1u << (src % 32u)));
}

void plic_disable(uint32_t src) {
  uint32_t enable = mmio_read32(PLIC_ENABLE(src));
  mmio_write32(PLIC_ENABLE(src), enable & ~(1u << (src % 32u)));
}

void plic_set_threshold(uint32_t threshold) {
  mmio_write32(PLIC_THRESHOLD, threshold);
}

uint32_t plic_claim(void) {
  return mmio_read32(PLIC_CLAIM);
}

void plic_complete(uint32_t id) {
  mmio_write32(PLIC_CLAIM, id);
}
