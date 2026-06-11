#include "dma.h"
#include "platform.h"
#include "printf.h"
#include "sim_ctrl.h"
#include "uart.h"

#define DMA_BUF_BYTES 1024u

static uint8_t src_buf[DMA_BUF_BYTES] __attribute__((aligned(8)));
static uint8_t dst_buf[DMA_BUF_BYTES] __attribute__((aligned(8)));

static int str_eq(const char *lhs, const char *rhs) {
  while (*lhs != '\0' && *rhs != '\0') {
    if (*lhs != *rhs) {
      return 0;
    }
    lhs++;
    rhs++;
  }

  return *lhs == *rhs;
}

static void fill_buffers(uint8_t seed) {
  for (uint32_t i = 0; i < DMA_BUF_BYTES; i++) {
    src_buf[i] = (uint8_t)(seed + (uint8_t)(i * 7u));
    dst_buf[i] = 0u;
  }
}

/* Copy len bytes from src_buf+src_off to dst_buf+dst_off via the DMA and
 * verify the destination, including that bytes around the window stayed
 * untouched. Returns 0 on success. */
static int run_case(const char *name, uint32_t src_off, uint32_t dst_off,
                    uint32_t len, uint8_t seed) {
  fill_buffers(seed);
  dma_memcpy((uintptr_t)&dst_buf[dst_off], (uintptr_t)&src_buf[src_off], len);

  for (uint32_t i = 0; i < DMA_BUF_BYTES; i++) {
    uint8_t expected;
    if (i >= dst_off && i < dst_off + len) {
      expected = src_buf[src_off + (i - dst_off)];
    } else {
      expected = 0u;
    }
    if (dst_buf[i] != expected) {
      printf("DMA FAIL [%s]: dst[%u] = 0x%02x, expected 0x%02x\n", name, i,
             dst_buf[i], expected);
      return 1;
    }
  }

  printf("DMA case %s: OK (%u bytes, src+%u -> dst+%u)\n", name, len, src_off,
         dst_off);
  return 0;
}

int main(void) {
  int failures = 0;

  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("=== CoreJack SoC Demo ===\n");
  printf("Target: %s\n", COREJACK_TARGET);
  printf("Core: %s\n", COREJACK_CORE);
  if (str_eq(COREJACK_TARGET, "fpga")) {
    printf("Board: %s\n", COREJACK_BOARD);
  }
  printf("DMA base: 0x%08x\n", DMA0_BASE);

  failures += run_case("aligned", 0u, 0u, 256u, 0x11u);
  failures += run_case("unaligned", 3u, 5u, 61u, 0x22u);
  failures += run_case("large", 0u, 0u, DMA_BUF_BYTES, 0x33u);

  if (failures != 0) {
    printf("DMA smoke FAILED (%d case%s)\n", failures,
           failures == 1 ? "" : "s");
    sim_ctrl_fail(1u);
  } else {
    printf("DMA memcpy path is alive.\n");
    if (str_eq(COREJACK_TARGET, "sim")) {
      printf("UART and sim_ctrl path are alive.\n");
    } else if (COREJACK_HAS_JTAG_DEBUG) {
      printf("UART and JTAG debug path are alive.\n");
    } else {
      printf("UART path is alive.\n");
    }
    sim_ctrl_pass();
  }

  while (1) {
#if COREJACK_HAS_JTAG_DEBUG
    __asm__ volatile("wfi");
#else
    __asm__ volatile("");
#endif
  }

  return 0;
}
