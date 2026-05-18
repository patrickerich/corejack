#include <stdint.h>

#include "printf.h"
#include "platform.h"
#include "sim_ctrl.h"
#include "uart.h"

#define BENCH_SMOKE_ITERS 4096u
#define BENCH_SMOKE_EXPECT_STATE 0xf5efd121u
#define BENCH_SMOKE_EXPECT_ACCUM 0x24ff9bbdu

static uint32_t rotl32(uint32_t value, unsigned int shift) {
  return (value << shift) | (value >> (32u - shift));
}

static void fail_u32(const char *name, uint32_t got, uint32_t expected,
                     uint32_t code) {
  if (got != expected) {
    printf("bench_smoke FAIL: %s got 0x%08x expected 0x%08x\n", name, got,
           expected);
    sim_ctrl_fail(code);
    while (1) {
      __asm__ volatile("wfi");
    }
  }
}

int main(void) {
  volatile uint32_t state = 0x6d2b79f5u;
  uint32_t accum = 0u;

  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("bench_smoke start\n");
  printf("iters: %u\n", BENCH_SMOKE_ITERS);

  for (uint32_t i = 0; i < BENCH_SMOKE_ITERS; ++i) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    accum = rotl32(accum, 7) ^ (state + (i * 0x9e3779b9u));
  }

  printf("state: 0x%08x\n", state);
  printf("accum: 0x%08x\n", accum);

  fail_u32("state", state, BENCH_SMOKE_EXPECT_STATE, 0x20u);
  fail_u32("accum", accum, BENCH_SMOKE_EXPECT_ACCUM, 0x21u);

  printf("bench_smoke pass\n");
  sim_ctrl_pass();

  while (1) {
    __asm__ volatile("wfi");
  }

  return 0;
}
