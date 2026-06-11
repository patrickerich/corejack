#ifndef COREJACK_PLIC_H_
#define COREJACK_PLIC_H_

#include <stdint.h>

#define PLIC0_BASE 0x0c000000u

/* Platform interrupt source IDs (PLIC source 0 is reserved by the spec). */
#define PLIC_SRC_UART0 1u
#define PLIC_SRC_DMA0  2u

/* Set the priority of a source (0 disables it; the platform implements
 * priorities 0..7). */
void plic_set_priority(uint32_t src, uint32_t prio);

/* Enable or disable a source for the M-mode context of hart 0. */
void plic_enable(uint32_t src);
void plic_disable(uint32_t src);

/* Only pending sources with a priority strictly greater than the threshold
 * raise the external interrupt. */
void plic_set_threshold(uint32_t threshold);

/* Claim the highest-priority pending source. Returns the source ID, or 0 if
 * nothing is pending. Every nonzero claim must be paired with a
 * plic_complete() of the same ID. */
uint32_t plic_claim(void);
void plic_complete(uint32_t id);

#endif
