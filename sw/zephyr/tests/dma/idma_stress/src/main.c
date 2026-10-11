/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Stress the CoreJack iDMA driver (sw/zephyr/drivers/dma/dma_corejack_idma.c)
 * where Zephyr's own DMA tests do not reach: multi-block transfers on two
 * channels sharing the iDMA's one queue, per-block callbacks, get_status,
 * -EBUSY, stop(), and the rejected configurations. Prints DMA STRESS PASS or
 * DMA STRESS FAIL at the end.
 */
#include <zephyr/device.h>
#include <zephyr/drivers/dma.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <string.h>

#define NBLK  4
#define CHUNK 4096
#define ROUNDS 40

static const struct device *const dma = DEVICE_DT_GET(DT_NODELABEL(dma0));

static uint8_t src[NBLK * CHUNK + 8];
static uint8_t dst0[NBLK * CHUNK + 8];
static uint8_t dst1[NBLK * CHUNK + 8];

struct chan_log {
	volatile uint32_t blocks;
	volatile uint32_t completes;
	volatile uint32_t seq; /* order in which the channel completed */
};
static struct chan_log logs[2];
static volatile uint32_t completion_seq;
static K_SEM_DEFINE(done_sem, 0, 2);

static void cb(const struct device *dev, void *user_data, uint32_t channel, int status)
{
	struct chan_log *log = &logs[channel];

	if (status == DMA_STATUS_BLOCK) {
		log->blocks++;
	} else if (status == DMA_STATUS_COMPLETE) {
		log->completes++;
		log->seq = ++completion_seq;
		k_sem_give(&done_sem);
	} else {
		printk("callback: channel %u status %d\n", channel, status);
	}
}

static int failures;

#define CHECK(cond, ...)                                                                           \
	do {                                                                                       \
		if (!(cond)) {                                                                     \
			printk("FAIL line %d: ", __LINE__);                                        \
			printk(__VA_ARGS__);                                                       \
			printk("\n");                                                              \
			failures++;                                                                \
		}                                                                                  \
	} while (0)

static void setup(struct dma_config *cfg, struct dma_block_config *blk, uint8_t *d,
		  uint32_t len, uint32_t soff, uint32_t doff, bool reverse, bool block_cb)
{
	memset(blk, 0, sizeof(*blk) * NBLK);
	for (int i = 0; i < NBLK; i++) {
		int j = reverse ? NBLK - 1 - i : i;

		blk[i].source_address = (uintptr_t)&src[soff + i * CHUNK];
		blk[i].dest_address = (uintptr_t)&d[doff + j * CHUNK];
		blk[i].block_size = len;
		blk[i].next_block = i < NBLK - 1 ? &blk[i + 1] : NULL;
	}
	*cfg = (struct dma_config){
		.channel_direction = MEMORY_TO_MEMORY,
		.complete_callback_en = block_cb,
		.block_count = NBLK,
		.head_block = blk,
		.dma_callback = cb,
	};
}

static bool same(const uint8_t *d, uint32_t len, uint32_t soff, uint32_t doff, bool reverse)
{
	for (int i = 0; i < NBLK; i++) {
		int j = reverse ? NBLK - 1 - i : i;

		if (memcmp(&d[doff + j * CHUNK], &src[soff + i * CHUNK], len) != 0) {
			return false;
		}
	}
	return true;
}

static void round_trip(uint32_t r)
{
	struct dma_config c0, c1;
	struct dma_block_config b0[NBLK], b1[NBLK];
	struct dma_status st;
	uint32_t len = CHUNK - (r % 7);      /* odd lengths */
	uint32_t soff = r % 5, doff = r % 3; /* unaligned addresses */
	uint32_t t0, t1, t2;

	for (uint32_t i = 0; i < sizeof(src); i++) {
		src[i] = (uint8_t)(i * 7U + r);
	}
	memset(dst0, 0, sizeof(dst0));
	memset(dst1, 0, sizeof(dst1));
	memset(logs, 0, sizeof(logs));
	completion_seq = 0;
	k_sem_reset(&done_sem);

	setup(&c0, b0, dst0, len, soff, doff, false, true);
	setup(&c1, b1, dst1, len, soff, doff, true, false);
	CHECK(dma_config(dma, 0, &c0) == 0, "config 0");
	CHECK(dma_config(dma, 1, &c1) == 0, "config 1");

	/* With interrupts locked nothing can complete, so ch1 is still busy
	 * for the restart check. */
	unsigned int key = irq_lock();

	t0 = k_cycle_get_32();
	CHECK(dma_start(dma, 0) == 0, "start 0");
	t1 = k_cycle_get_32();
	CHECK(dma_start(dma, 1) == 0, "start 1");
	t2 = k_cycle_get_32();
	CHECK(dma_start(dma, 1) == -EBUSY, "restart while busy");
	CHECK(dma_get_status(dma, 1, &st) == 0, "status 1");
	irq_unlock(key);
	if (r == 0) {
		printk("round 0: start0 %u us, start1 %u us (4 x %u B each); ch1 busy %d "
		       "pending %u\n", k_cyc_to_us_floor32(t1 - t0),
		       k_cyc_to_us_floor32(t2 - t1), len, st.busy, st.pending_length);
	}

	CHECK(k_sem_take(&done_sem, K_MSEC(500)) == 0, "first completion");
	CHECK(k_sem_take(&done_sem, K_MSEC(500)) == 0, "second completion");

	CHECK(logs[0].blocks == NBLK - 1 && logs[0].completes == 1,
	      "ch0 callbacks: %u block, %u complete", logs[0].blocks, logs[0].completes);
	CHECK(logs[1].blocks == 0 && logs[1].completes == 1,
	      "ch1 callbacks: %u block, %u complete", logs[1].blocks, logs[1].completes);
	CHECK(logs[0].seq == 1 && logs[1].seq == 2, "completion order %u %u", logs[0].seq,
	      logs[1].seq);
	CHECK(same(dst0, len, soff, doff, false), "ch0 data, round %u", r);
	CHECK(same(dst1, len, soff, doff, true), "ch1 data, round %u", r);
	CHECK(dma_get_status(dma, 0, &st) == 0 && !st.busy && st.pending_length == 0,
	      "ch0 idle after");
}

static void stop_case(void)
{
	struct dma_config c0;
	struct dma_block_config b0[NBLK];
	struct dma_status st;

	memset(dst0, 0, sizeof(dst0));
	memset(logs, 0, sizeof(logs));
	k_sem_reset(&done_sem);
	setup(&c0, b0, dst0, CHUNK, 0, 0, false, true);
	CHECK(dma_config(dma, 0, &c0) == 0, "stop: config");
	/* Stop before the completion interrupt can run. */
	unsigned int key = irq_lock();

	CHECK(dma_start(dma, 0) == 0, "stop: start");
	CHECK(dma_stop(dma, 0) == 0, "stop: stop");
	irq_unlock(key);
	CHECK(dma_get_status(dma, 0, &st) == 0 && !st.busy, "stop: idle after stop");
	CHECK(same(dst0, CHUNK, 0, 0, false), "stop: copies finished");
	k_msleep(10);
	CHECK(logs[0].blocks == 0 && logs[0].completes == 0, "stop: no callbacks (%u, %u)",
	      logs[0].blocks, logs[0].completes);
	/* The channel is reusable after a stop. */
	CHECK(dma_start(dma, 0) == 0, "stop: restart");
	CHECK(k_sem_take(&done_sem, K_MSEC(500)) == 0, "stop: restart completes");
}

static void reject_case(void)
{
	struct dma_config c;
	struct dma_block_config b[NBLK];

	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	b[0].source_address = 0x10000000; /* the UART */
	CHECK(dma_config(dma, 0, &c) == -EINVAL, "reject: source outside RAM");
	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	b[1].dest_address = 0x90000000; /* past every board's RAM */
	CHECK(dma_config(dma, 0, &c) == -EINVAL, "reject: dest past RAM");
	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	c.cyclic = 1;
	CHECK(dma_config(dma, 0, &c) == -ENOTSUP, "reject: cyclic");
	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	b[2].dest_addr_adj = DMA_ADDR_ADJ_NO_CHANGE;
	CHECK(dma_config(dma, 0, &c) == -ENOTSUP, "reject: fixed address");
	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	b[0].source_gather_en = 1;
	b[0].source_gather_interval = 16;
	CHECK(dma_config(dma, 0, &c) == -ENOTSUP, "reject: real gather");
	setup(&c, b, dst0, CHUNK, 0, 0, false, false);
	c.block_count = 17;
	CHECK(dma_config(dma, 0, &c) == -EINVAL, "reject: 17 blocks");
	CHECK(dma_config(dma, 4, &c) == -EINVAL, "reject: channel 4");
}

int main(void)
{
	printk("idma stress on %s\n", dma->name);
	if (!device_is_ready(dma)) {
		printk("DMA STRESS FAIL: device not ready\n");
		return 0;
	}
	for (uint32_t r = 0; r < ROUNDS; r++) {
		round_trip(r);
	}
	stop_case();
	reject_case();
	if (failures == 0) {
		printk("DMA STRESS PASS (%d rounds)\n", ROUNDS);
	} else {
		printk("DMA STRESS FAIL (%d failures)\n", failures);
	}
	return 0;
}
