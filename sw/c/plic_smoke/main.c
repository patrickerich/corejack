#include <stdint.h>

#include "platform.h"
#include "plic.h"
#include "printf.h"
#include "sim_ctrl.h"
#include "uart.h"

/* The UART's 16550 interrupt-enable register; bit 1 raises the interrupt
 * line whenever the transmit holding register is empty, which makes it a
 * deterministic PLIC source once the console output has drained. */
#define UART_IER           (UART0_BASE + 0x04u)
#define UART_IER_THR_EMPTY 0x02u

#define MSTATUS_MIE (1u << 3)
#define MIE_MEIE    (1u << 11)

#define SPIN_LIMIT 200000u

static volatile uint32_t ext_seen;
static volatile uint32_t ext_claimed_id;

static inline void mmio_write8(uint32_t addr, uint8_t value) {
  *(volatile uint8_t *)(uintptr_t)addr = value;
}

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

/* crt0.S vector table; mtvec points here in vectored mode, which is what
 * the vectored-only cores (Ibex, CV32E40*) require. */
extern const char _vectors[];

/* External-interrupt slot of the crt0 vector table (overrides the weak
 * default). Claim first, then silence the UART, then complete: completing
 * while the level source is still asserted would immediately pend it
 * again. */
void corejack_external_vector(void) __attribute__((interrupt("machine")));
void corejack_external_vector(void) {
  uint32_t id = plic_claim();

  if (id == PLIC_SRC_UART0) {
    mmio_write8(UART_IER, 0u);
  }
  plic_complete(id);

  ext_claimed_id = id;
  ext_seen = 1u;
}

/* Poll-mode claim/complete with the core's interrupts left disabled. */
static int run_case_poll(void) {
  uint32_t id = 0u;

  mmio_write8(UART_IER, UART_IER_THR_EMPTY);
  for (uint32_t i = 0; i < SPIN_LIMIT && id == 0u; i++) {
    id = plic_claim();
  }
  mmio_write8(UART_IER, 0u);

  if (id != PLIC_SRC_UART0) {
    printf("PLIC FAIL [poll]: claim returned %u, expected %u\n", id,
           PLIC_SRC_UART0);
    return 1;
  }
  plic_complete(id);

  printf("PLIC case poll: OK (claimed source %u)\n", id);
  return 0;
}

/* With the threshold at the maximum, the pending source must not reach the
 * core even though interrupts are globally enabled. */
static int run_case_masked(void) {
  ext_seen = 0u;
  plic_set_threshold(7u);
  mmio_write8(UART_IER, UART_IER_THR_EMPTY);

  for (volatile uint32_t i = 0; i < SPIN_LIMIT / 10u; i++) {
  }

  if (ext_seen != 0u) {
    printf("PLIC FAIL [masked]: interrupt taken despite threshold\n");
    return 1;
  }

  printf("PLIC case masked: OK (threshold gated the interrupt)\n");
  return 0;
}

/* Dropping the threshold releases the already-pending source and the core
 * takes the external interrupt. */
static int run_case_interrupt(void) {
  plic_set_threshold(0u);

  for (uint32_t i = 0; i < SPIN_LIMIT && ext_seen == 0u; i++) {
  }

  if (ext_seen == 0u) {
    printf("PLIC FAIL [interrupt]: external interrupt never arrived\n");
    return 1;
  }
  if (ext_claimed_id != PLIC_SRC_UART0) {
    printf("PLIC FAIL [interrupt]: claimed %u, expected %u\n", ext_claimed_id,
           PLIC_SRC_UART0);
    return 1;
  }

  printf("PLIC case interrupt: OK (claimed source %u in the ISR)\n",
         ext_claimed_id);
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
  printf("PLIC base: 0x%08x\n", PLIC0_BASE);

  plic_set_priority(PLIC_SRC_UART0, 1u);
  plic_set_threshold(0u);
  plic_enable(PLIC_SRC_UART0);

  failures += run_case_poll();

  csr_write_mtvec((uintptr_t)_vectors | 1u);  /* vectored mode */
  csr_set_mie(MIE_MEIE);
  csr_set_mstatus(MSTATUS_MIE);

  failures += run_case_masked();
  failures += run_case_interrupt();

  csr_clear_mstatus(MSTATUS_MIE);
  plic_disable(PLIC_SRC_UART0);

  if (failures != 0) {
    printf("PLIC smoke FAILED (%d case%s)\n", failures,
           failures == 1 ? "" : "s");
    sim_ctrl_fail(1u);
  } else {
    printf("PLIC external interrupt path is alive.\n");
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
