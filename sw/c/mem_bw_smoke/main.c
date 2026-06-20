/* System-level CPU + iDMA memory-bandwidth concurrency benchmark.
 *
 * Measures whether CPU memory traffic and a concurrent iDMA RAM-to-RAM copy
 * make progress in parallel through the fabric, or serialize against each
 * other. The CPU runs a load/store streaming loop over its own RAM buffer
 * while the iDMA copies a separate buffer; cycle counts come from the mcycle
 * CSR (independent of the baud-throttled UART), so the figures are accurate
 * regardless of simulation print speed.
 *
 * Reported (decimal cycles):
 *   cpu_alone  - CPU stream loop with no DMA running
 *   dma_alone  - iDMA copy with no CPU traffic
 *   cpu_dma    - CPU stream loop launched under a concurrent iDMA copy
 *   slowdown   - cpu_dma / cpu_alone, x1000 (1000 = the CPU is untouched by the
 *                DMA; ~2000 = fully serialized behind it)
 *   overlap    - (cpu_alone + dma_alone) / total-overlap-window, x1000
 *                (1000 = serialized, ~2000 = perfect overlap)
 *
 * The iDMA is sized to outlast the CPU loop (it is ~tens of times faster per
 * word than the CPU's load/store loop on the current single-outstanding RAM
 * path), so the whole CPU measurement happens under DMA load.
 *
 * Functional gates: the iDMA copy must move its marker words into the
 * destination, and the CPU loop must return the same checksum with and without
 * the concurrent DMA (proving the DMA touched only its own buffers). The
 * concurrency assertion is deliberately lenient - it guards against a
 * catastrophic serialization regression; the headline numbers are the
 * before/after instrument.
 *
 * Uses the mcycle CSR (RV32 cores with the standard counter: ibex, cv32e40*,
 * cva6). Not intended for serv/picorv32.
 */

#include <stdint.h>

#include "dma.h"
#include "platform.h"
#include "printf.h"
#include "sim_ctrl.h"
#include "uart.h"

#define CPU_WORDS 64u    /* 256 B CPU streaming buffer */
#define CPU_PASSES 1u    /* load+store passes over the buffer per timed run */
#define DMA_WORDS 6144u  /* 24 KiB iDMA copy; sized to outlast the CPU loop */
#define MARK_STRIDE 389u /* sparse marker spacing for the copy correctness check */

static volatile uint32_t cpu_buf[CPU_WORDS];
static uint32_t dma_src[DMA_WORDS];
static uint32_t dma_dst[DMA_WORDS];

static inline uint32_t read_mcycle(void) {
  uint32_t c;
  __asm__ volatile(".option arch,+zicsr\n"
                   "csrr %0, mcycle\n"
                   : "=r"(c));
  return c;
}

/* Reset the CPU buffer to a fixed pattern so each timed run starts from an
 * identical state and must return the same checksum. */
static void cpu_buf_init(void) {
  for (uint32_t i = 0; i < CPU_WORDS; ++i) {
    cpu_buf[i] = 0x9e3779b9u * (i + 1u);
  }
}

/* Streaming load + store loop: real RAM data traffic that cannot be optimized
 * into registers (cpu_buf is volatile). Deterministic for a given initial
 * buffer state. */
static uint32_t cpu_stream(uint32_t passes) {
  uint32_t acc = 0x12345678u;
  for (uint32_t p = 0; p < passes; ++p) {
    for (uint32_t i = 0; i < CPU_WORDS; ++i) {
      uint32_t v = cpu_buf[i];
      acc = (acc ^ v) + ((acc << 3) | (acc >> 29));
      cpu_buf[i] = acc;
    }
  }
  return acc;
}

/* Seed sparse marker words in the iDMA source (the rest stays crt0-zeroed; a
 * zero->zero copy still generates the same RAM traffic). */
static void dma_src_mark(void) {
  for (uint32_t i = 0; i < DMA_WORDS; i += MARK_STRIDE) {
    dma_src[i] = 0xabcd0000u | i;
  }
}

/* Clear the marker positions in the destination so a later copy must restore
 * them for the check to pass. */
static void dma_dst_clear_marks(void) {
  for (uint32_t i = 0; i < DMA_WORDS; i += MARK_STRIDE) {
    dma_dst[i] = 0u;
  }
}

static int dma_marks_ok(void) {
  for (uint32_t i = 0; i < DMA_WORDS; i += MARK_STRIDE) {
    if (dma_dst[i] != dma_src[i]) {
      return 0;
    }
  }
  return 1;
}

static void fail(const char *what, uint32_t code) {
  printf("mem_bw FAIL: %s\n", what);
  sim_ctrl_fail(code);
  while (1) {
    __asm__ volatile("wfi");
  }
}

int main(void) {
  uart_init(UART0_BASE, COREJACK_CORE_CLK_HZ, COREJACK_UART_BAUD);
  printf("mem_bw start\n");

  dma_src_mark();

  /* --- CPU stream alone --------------------------------------------------- */
  cpu_buf_init();
  uint32_t t0 = read_mcycle();
  uint32_t cpu_ref = cpu_stream(CPU_PASSES);
  uint32_t cpu_alone = read_mcycle() - t0;

  /* --- iDMA copy alone ---------------------------------------------------- */
  dma_dst_clear_marks();
  t0 = read_mcycle();
  dma_memcpy((uintptr_t)dma_dst, (uintptr_t)dma_src, DMA_WORDS * 4u);
  uint32_t dma_alone = read_mcycle() - t0;
  if (!dma_marks_ok()) {
    fail("dma copy mismatch", 0x30u);
  }

  /* --- CPU stream under a concurrent iDMA copy ---------------------------- */
  cpu_buf_init();
  dma_dst_clear_marks();
  uint32_t ov0 = read_mcycle();
  uint32_t id = dma_memcpy_start((uintptr_t)dma_dst, (uintptr_t)dma_src,
                                 DMA_WORDS * 4u);
  uint32_t cpu_cmp = cpu_stream(CPU_PASSES);
  uint32_t cpu_dma = read_mcycle() - ov0;
  dma_wait(id);
  uint32_t overlap = read_mcycle() - ov0;

  /* Functional gates. */
  if (cpu_cmp != cpu_ref) {
    fail("cpu checksum diverged under dma", 0x31u);
  }
  if (!dma_marks_ok()) {
    fail("concurrent dma copy mismatch", 0x32u);
  }
  if (cpu_alone == 0u || dma_alone == 0u) {
    fail("mcycle not counting", 0x33u);
  }

  /* Derived metrics, x1000 to avoid floating point. */
  uint32_t slowdown = (uint32_t)(((uint64_t)cpu_dma * 1000u) / cpu_alone);
  uint32_t overlap_eff =
      (uint32_t)((((uint64_t)cpu_alone + dma_alone) * 1000u) / overlap);

  printf("cpu_alone %u\n", cpu_alone);
  printf("dma_alone %u\n", dma_alone);
  printf("cpu_dma %u\n", cpu_dma);
  printf("slowdown %u\n", slowdown);
  printf("overlap %u\n", overlap_eff);

  /* Lenient regression guard: a fully serialized fabric would roughly double
   * the CPU loop time (slowdown ~2000); anything well below that confirms the
   * CPU and iDMA are not funnelled through one shared RAM port. */
  if (slowdown > 2500u) {
    fail("cpu serialized behind dma", 0x34u);
  }

  printf("mem_bw pass\n");
  sim_ctrl_pass();

  while (1) {
    __asm__ volatile("wfi");
  }
  return 0;
}
