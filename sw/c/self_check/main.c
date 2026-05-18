#include <stdint.h>

#include "printf.h"
#include "platform.h"
#include "sim_ctrl.h"
#include "uart.h"

static void check_u32(const char *name, uint32_t got, uint32_t expected, uint32_t fail_code) {
  if (got != expected) {
    printf("FAIL: %s got 0x%08x expected 0x%08x\n", name, got, expected);
    sim_ctrl_fail(fail_code);
    while (1) {
      __asm__ volatile("wfi");
    }
  }
}

int main(void) {
  volatile uint32_t seed = 0x12345678u;
  uint32_t accum = 0u;

  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("self_check start\n");

  for (uint32_t i = 0; i < 8; ++i) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    accum += seed;
  }

  check_u32("accum", accum, 0x4f8dc7bfu, 0x10u);
  check_u32("xor", seed ^ accum, 0x8a95a996u, 0x12u);

  printf("self_check pass\n");
  sim_ctrl_pass();

  while (1) {
    __asm__ volatile("wfi");
  }

  return 0;
}
