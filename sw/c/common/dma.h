#ifndef COREJACK_DMA_H_
#define COREJACK_DMA_H_

#include <stdint.h>

/* iDMA system DMA (rtl/platform/soc_idma.sv): PULP iDMA behind the
 * idma_reg32_3d register frontend. Register window declared in soc_top
 * (DmaBaseAddr). */
#define DMA0_BASE 0x01000000u

/* idma_reg32_3d register offsets (see
 * deps/idma/target/rtl/idma_reg32_3d_reg_pkg.sv). */
#define DMA_REG_CONF 0x00u      /* 0 = plain 1D AXI-to-AXI transfer */
#define DMA_REG_STATUS_0 0x04u  /* busy bits of stream 0 */
#define DMA_REG_NEXT_ID_0 0x44u /* read launches the transfer, returns id */
#define DMA_REG_DONE_ID_0 0x84u /* id of the most recent completed transfer */
#define DMA_REG_DST_ADDR 0xd0u
#define DMA_REG_SRC_ADDR 0xd8u
#define DMA_REG_LENGTH 0xe0u

/* CoreJack completion-interrupt status register, implemented in the socket
 * adapter (corejack_idma_socket_adapter) beside the iDMA register block.
 * Bit 0 reads the sticky completion flag (the level on PLIC source 2);
 * writing 1 to bit 0 clears it. Interrupt handlers must clear it here
 * before completing the claim at the PLIC, or the still-high level pends
 * again immediately. */
#define DMA_REG_IRQ_STATUS 0xf00u

/* Start a 1D memory-to-memory copy of len bytes; returns the transfer id. */
uint32_t dma_memcpy_start(uintptr_t dst, uintptr_t src, uint32_t len);

/* Block until the given transfer id has completed. */
void dma_wait(uint32_t transfer_id);

/* Convenience: start a copy and wait for completion. */
void dma_memcpy(uintptr_t dst, uintptr_t src, uint32_t len);

/* Completion-interrupt helpers (PLIC source 2). */
uint32_t dma_irq_pending(void);
void dma_irq_ack(void);

#endif
