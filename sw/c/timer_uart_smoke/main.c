#include <stdint.h>

#include "printf.h"
#include "platform.h"
#include "sim_ctrl.h"
#include "uart.h"

#define CLINT_MTIMECMP_LO 0x02004000u
#define CLINT_MTIMECMP_HI 0x02004004u
#define CLINT_MTIME_LO    0x0200bff8u
#define CLINT_MTIME_HI    0x0200bffcu

#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)

static volatile uint32_t timer_seen;

static inline uint32_t mmio_read32(uint32_t addr) {
  return *(volatile uint32_t *)(uintptr_t)addr;
}

static inline void mmio_write32(uint32_t addr, uint32_t value) {
  *(volatile uint32_t *)(uintptr_t)addr = value;
}

static inline void csr_write_mtvec(uint32_t value) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrw mtvec, %0\n"
                   ".option pop" : : "r"(value));
}

static inline void csr_set_mie(uint32_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrs mie, %0\n"
                   ".option pop" : : "r"(mask));
}

static inline void csr_clear_mie(uint32_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrc mie, %0\n"
                   ".option pop" : : "r"(mask));
}

static inline void csr_set_mstatus(uint32_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrs mstatus, %0\n"
                   ".option pop" : : "r"(mask));
}

static inline void csr_clear_mstatus(uint32_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrc mstatus, %0\n"
                   ".option pop" : : "r"(mask));
}

static uint64_t read_mtime(void) {
  uint32_t hi0;
  uint32_t lo;
  uint32_t hi1;

  do {
    hi0 = mmio_read32(CLINT_MTIME_HI);
    lo = mmio_read32(CLINT_MTIME_LO);
    hi1 = mmio_read32(CLINT_MTIME_HI);
  } while (hi0 != hi1);

  return ((uint64_t)hi0 << 32) | lo;
}

static void write_mtimecmp(uint64_t value) {
  mmio_write32(CLINT_MTIMECMP_HI, 0xffffffffu);
  mmio_write32(CLINT_MTIMECMP_LO, (uint32_t)value);
  mmio_write32(CLINT_MTIMECMP_HI, (uint32_t)(value >> 32));
}

// CV32E40X/CV32E40S CLINT-mode mtvec bases are WARL-aligned to 128 bytes.
void timer_isr(void) __attribute__((interrupt("machine"), aligned(128)));
void timer_isr(void) {
  timer_seen = 1u;
  write_mtimecmp(UINT64_MAX);
}

int main(void) {
  uint64_t now;

  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("timer_uart_smoke start\n");
  printf("Core: " COREJACK_CORE "\n");

  timer_seen = 0u;
  csr_write_mtvec((uint32_t)(uintptr_t)&timer_isr);

  now = read_mtime();
  write_mtimecmp(now + 1000u);

  csr_set_mie(MIE_MTIE);
  csr_set_mstatus(MSTATUS_MIE);

  while (timer_seen == 0u) {
    __asm__ volatile("wfi");
  }

  csr_clear_mstatus(MSTATUS_MIE);
  csr_clear_mie(MIE_MTIE);

  printf("timer_uart_smoke timer interrupt observed\n");
  printf("timer_uart_smoke pass\n");
  sim_ctrl_pass();

  while (1) {
    __asm__ volatile("wfi");
  }

  return 0;
}
