#include "dma.h"
#include "platform.h"
#include "plic.h"
#include "printf.h"
#include "sim_ctrl.h"
#include "uart.h"

#define DMA_BUF_BYTES 1024u

#define MSTATUS_MIE (1u << 3)
#define MIE_MEIE    (1u << 11)

#define IRQ_SPIN_LIMIT 200000u

static uint8_t src_buf[DMA_BUF_BYTES] __attribute__((aligned(8)));
static uint8_t dst_buf[DMA_BUF_BYTES] __attribute__((aligned(8)));

#if COREJACK_HAS_EXT_IRQ
static volatile uint32_t dma_irq_seen;
static volatile uint32_t dma_irq_claimed_id;

/* crt0.S vector table; mtvec points here in vectored mode. */
extern const char _vectors[];

static inline void csr_write_mtvec(uintptr_t value) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrw mtvec, %0\n"
                   ".option pop" : : "r"(value));
}

static inline void csr_set_mie(uintptr_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrs mie, %0\n"
                   ".option pop" : : "r"(mask));
}

static inline void csr_set_mstatus(uintptr_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrs mstatus, %0\n"
                   ".option pop" : : "r"(mask));
}

static inline void csr_clear_mstatus(uintptr_t mask) {
  __asm__ volatile(".option push\n"
                   ".option arch,+zicsr\n"
                   "csrc mstatus, %0\n"
                   ".option pop" : : "r"(mask));
}

/* External-interrupt slot of the crt0 vector table. Acknowledge the level
 * source at the DMA before completing at the PLIC, or it pends again. */
void corejack_external_vector(void) __attribute__((interrupt("machine")));
void corejack_external_vector(void) {
  uint32_t id = plic_claim();

  if (id == PLIC_SRC_DMA0) {
    dma_irq_ack();
  }
  plic_complete(id);

  dma_irq_claimed_id = id;
  dma_irq_seen = 1u;
}
#endif

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

#if COREJACK_HAS_EXT_IRQ
/* Interrupt-driven completion: the copy is started without polling and the
 * ISR observes it through PLIC source 2 (claim, dma_irq_ack, complete). */
static int run_case_irq(void) {
  fill_buffers(0x44u);

  plic_set_priority(PLIC_SRC_DMA0, 1u);
  plic_set_threshold(0u);
  plic_enable(PLIC_SRC_DMA0);
  csr_write_mtvec((uintptr_t)_vectors | 1u);  /* vectored mode */
  csr_set_mie(MIE_MEIE);
  csr_set_mstatus(MSTATUS_MIE);

  dma_irq_seen = 0u;
  (void)dma_memcpy_start((uintptr_t)dst_buf, (uintptr_t)src_buf, 256u);

  for (uint32_t i = 0; i < IRQ_SPIN_LIMIT && dma_irq_seen == 0u; i++) {
  }

  csr_clear_mstatus(MSTATUS_MIE);
  plic_disable(PLIC_SRC_DMA0);

  if (dma_irq_seen == 0u) {
    printf("DMA FAIL [irq]: completion interrupt never arrived\n");
    return 1;
  }
  if (dma_irq_claimed_id != PLIC_SRC_DMA0) {
    printf("DMA FAIL [irq]: claimed %u, expected %u\n", dma_irq_claimed_id,
           PLIC_SRC_DMA0);
    return 1;
  }
  if (dma_irq_pending() != 0u) {
    printf("DMA FAIL [irq]: completion flag still pending after ack\n");
    return 1;
  }
  for (uint32_t i = 0; i < 256u; i++) {
    if (dst_buf[i] != src_buf[i]) {
      printf("DMA FAIL [irq]: dst[%u] = 0x%02x, expected 0x%02x\n", i,
             dst_buf[i], src_buf[i]);
      return 1;
    }
  }

  printf("DMA case irq: OK (claimed source %u in the ISR)\n",
         dma_irq_claimed_id);
  return 0;
}
#endif

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
#if COREJACK_HAS_EXT_IRQ
  failures += run_case_irq();
#endif

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
