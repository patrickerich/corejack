/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Zephyr DMA driver for the CoreJack iDMA (rtl/platform/soc_idma.sv): the PULP
 * iDMA behind its idma_reg32_3d register frontend, with CoreJack's completion
 * flag on a PLIC source. It copies memory to memory, within RAM only - the
 * iDMA's data path reaches the RAM and nothing else.
 *
 * The hardware has one transfer queue. A launch writes the addresses and
 * length and then reads NEXT_ID, which queues the copy and returns its id;
 * copies retire in launch order, and DONE_ID holds the id of the last one to
 * retire. The logical channels share that queue: a channel launches one copy
 * per block, remembers the ids, and completes once DONE_ID reaches its last
 * id. A launch into a full queue stalls the NEXT_ID read until a queued copy
 * retires, and start() launches all of a transfer's blocks with interrupts
 * masked: a start of many large blocks keeps interrupts masked for about the
 * time all but its first one or two copies take.
 */

#define DT_DRV_COMPAT corejack_idma

#include <zephyr/device.h>
#include <zephyr/drivers/dma.h>
#include <zephyr/irq.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/spinlock.h>
#include <zephyr/sys/sys_io.h>
#include <zephyr/sys/util.h>

#include <string.h>

LOG_MODULE_REGISTER(dma_corejack_idma, CONFIG_DMA_LOG_LEVEL);

/* idma_reg32_3d registers for stream 0 (see
 * deps/idma/target/rtl/idma_reg32_3d_reg_pkg.sv), and CoreJack's completion
 * flag (corejack_idma_socket_adapter). */
#define IDMA_CONF       0x000 /* 0: a plain 1D copy, AXI to AXI */
#define IDMA_NEXT_ID    0x044 /* read: launch the copy, returns its id */
#define IDMA_DONE_ID    0x084 /* id of the last retired copy */
#define IDMA_DST_ADDR   0x0d0
#define IDMA_SRC_ADDR   0x0d8
#define IDMA_LENGTH     0x0e0
#define IDMA_IRQ_STATUS 0xf00 /* bit 0: sticky completion flag, write 1 to clear */

/* Blocks per transfer; each block is one queued copy. */
#define IDMA_MAX_BLOCKS 16

/* The RAM the iDMA reaches: the zephyr,flash and zephyr,sram regions, which
 * are the two halves of CoreJack's one SRAM. */
#define IDMA_RAM_START ((uint64_t)DT_REG_ADDR(DT_CHOSEN(zephyr_flash)))
#define IDMA_RAM_END                                                               \
	((uint64_t)DT_REG_ADDR(DT_CHOSEN(zephyr_sram)) + DT_REG_SIZE(DT_CHOSEN(zephyr_sram)))
BUILD_ASSERT(DT_REG_ADDR(DT_CHOSEN(zephyr_flash)) + DT_REG_SIZE(DT_CHOSEN(zephyr_flash)) ==
		     DT_REG_ADDR(DT_CHOSEN(zephyr_sram)),
	     "the iDMA RAM check assumes zephyr,sram directly follows zephyr,flash");

struct idma_block {
	uint32_t src;
	uint32_t dst;
	uint32_t len;
};

struct idma_channel {
	struct idma_block blocks[IDMA_MAX_BLOCKS];
	uint32_t block_count;
	dma_callback_t callback;
	void *user_data;
	bool block_callbacks;
	bool configured;
	bool busy;
	bool stopping;
	/* Ids of the running transfer's first and last block, and of the last
	 * block reported to the callback. */
	uint32_t first_id;
	uint32_t last_id;
	uint32_t reported_id;
};

struct idma_config {
	uintptr_t base;
	uint32_t channels;
	void (*irq_configure)(void);
};

struct idma_data {
	/* First member: dma_request_channel() reads it through dev->data. */
	struct dma_context ctx;
	struct k_spinlock lock;
	struct idma_channel *channels;
};

static inline uint32_t idma_read(const struct device *dev, uint32_t reg)
{
	const struct idma_config *cfg = dev->config;

	return sys_read32(cfg->base + reg);
}

static inline void idma_write(const struct device *dev, uint32_t reg, uint32_t value)
{
	const struct idma_config *cfg = dev->config;

	sys_write32(value, cfg->base + reg);
}

/* True once DONE_ID has reached id. Ids count up and wrap at 32 bits, so
 * compare the signed difference. */
static inline bool idma_retired(uint32_t done_id, uint32_t id)
{
	return (int32_t)(done_id - id) >= 0;
}

static bool idma_in_ram(uint64_t addr, uint32_t len)
{
	return addr >= IDMA_RAM_START && addr + len <= IDMA_RAM_END && addr + len <= BIT64(32);
}

static int idma_check_block(const struct dma_block_config *block)
{
	if (block->block_size == 0U) {
		LOG_ERR("empty block");
		return -EINVAL;
	}
	/* A gather or scatter with no interval and no count is a plain copy;
	 * Zephyr's scatter_gather test sets the flags that way for a block list. */
	if (block->source_addr_adj != DMA_ADDR_ADJ_INCREMENT ||
	    block->dest_addr_adj != DMA_ADDR_ADJ_INCREMENT || block->source_gather_interval ||
	    block->source_gather_count || block->dest_scatter_interval ||
	    block->dest_scatter_count || block->source_reload_en || block->dest_reload_en) {
		LOG_ERR("only plain incrementing copies are supported");
		return -ENOTSUP;
	}
	if (!idma_in_ram(block->source_address, block->block_size) ||
	    !idma_in_ram(block->dest_address, block->block_size)) {
		LOG_ERR("copy outside RAM: 0x%llx -> 0x%llx, %u bytes",
			(unsigned long long)block->source_address,
			(unsigned long long)block->dest_address, block->block_size);
		return -EINVAL;
	}
	return 0;
}

static int idma_config(const struct device *dev, uint32_t channel, struct dma_config *config)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	struct idma_block blocks[IDMA_MAX_BLOCKS];
	const struct dma_block_config *block = config->head_block;
	struct idma_channel *chan;
	k_spinlock_key_t key;
	int ret;

	if (channel >= cfg->channels) {
		return -EINVAL;
	}
	if (config->channel_direction != MEMORY_TO_MEMORY || config->cyclic ||
	    config->source_chaining_en || config->dest_chaining_en) {
		LOG_ERR("only single memory-to-memory transfers are supported");
		return -ENOTSUP;
	}
	if (config->block_count == 0U || config->block_count > IDMA_MAX_BLOCKS) {
		LOG_ERR("block_count %u outside 1..%u", config->block_count, IDMA_MAX_BLOCKS);
		return -EINVAL;
	}
	for (uint32_t i = 0; i < config->block_count; i++) {
		if (block == NULL) {
			return -EINVAL;
		}
		ret = idma_check_block(block);
		if (ret != 0) {
			return ret;
		}
		blocks[i] = (struct idma_block){
			.src = (uint32_t)block->source_address,
			.dst = (uint32_t)block->dest_address,
			.len = block->block_size,
		};
		block = block->next_block;
	}

	chan = &data->channels[channel];
	key = k_spin_lock(&data->lock);
	if (chan->busy) {
		k_spin_unlock(&data->lock, key);
		return -EBUSY;
	}
	memcpy(chan->blocks, blocks, sizeof(blocks[0]) * config->block_count);
	chan->block_count = config->block_count;
	chan->callback = config->dma_callback;
	chan->user_data = config->user_data;
	chan->block_callbacks = config->complete_callback_en;
	chan->configured = true;
	k_spin_unlock(&data->lock, key);
	return 0;
}

/* Zephyr passes 64-bit addresses only with CONFIG_DMA_64BIT. */
#ifdef CONFIG_DMA_64BIT
typedef uint64_t idma_addr_t;
#else
typedef uint32_t idma_addr_t;
#endif

static int idma_reload(const struct device *dev, uint32_t channel, idma_addr_t src,
		       idma_addr_t dst, size_t size)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	struct idma_channel *chan;
	k_spinlock_key_t key;

	if (channel >= cfg->channels) {
		return -EINVAL;
	}
	if (size == 0U || size > UINT32_MAX || !idma_in_ram(src, size) ||
	    !idma_in_ram(dst, size)) {
		return -EINVAL;
	}

	chan = &data->channels[channel];
	key = k_spin_lock(&data->lock);
	if (!chan->configured || chan->busy) {
		k_spin_unlock(&data->lock, key);
		return chan->busy ? -EBUSY : -EINVAL;
	}
	/* The next start copies this one block. */
	chan->blocks[0] = (struct idma_block){
		.src = (uint32_t)src,
		.dst = (uint32_t)dst,
		.len = (uint32_t)size,
	};
	chan->block_count = 1U;
	k_spin_unlock(&data->lock, key);
	return 0;
}

static int idma_start(const struct device *dev, uint32_t channel)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	struct idma_channel *chan;
	k_spinlock_key_t key;

	if (channel >= cfg->channels) {
		return -EINVAL;
	}

	chan = &data->channels[channel];
	/* The launches and the bookkeeping go together under the lock: a short
	 * copy can retire straight away, and the interrupt must then find the
	 * channel already busy with its ids recorded. */
	key = k_spin_lock(&data->lock);
	if (!chan->configured || chan->busy) {
		k_spin_unlock(&data->lock, key);
		return chan->busy ? -EBUSY : -EINVAL;
	}
	for (uint32_t i = 0; i < chan->block_count; i++) {
		uint32_t id;

		idma_write(dev, IDMA_DST_ADDR, chan->blocks[i].dst);
		idma_write(dev, IDMA_SRC_ADDR, chan->blocks[i].src);
		idma_write(dev, IDMA_LENGTH, chan->blocks[i].len);
		idma_write(dev, IDMA_CONF, 0U);
		id = idma_read(dev, IDMA_NEXT_ID);
		if (i == 0U) {
			chan->first_id = id;
		}
		chan->last_id = id;
	}
	chan->reported_id = chan->first_id - 1U;
	chan->stopping = false;
	chan->busy = true;
	k_spin_unlock(&data->lock, key);
	return 0;
}

/* The iDMA cannot cancel a copy it has queued, so stop waits for the channel's
 * copies to retire, without calling its callback. */
static int idma_stop(const struct device *dev, uint32_t channel)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	struct idma_channel *chan;
	k_spinlock_key_t key;
	uint32_t last_id;

	if (channel >= cfg->channels) {
		return -EINVAL;
	}

	chan = &data->channels[channel];
	key = k_spin_lock(&data->lock);
	if (!chan->busy) {
		k_spin_unlock(&data->lock, key);
		return 0;
	}
	chan->stopping = true;
	last_id = chan->last_id;
	k_spin_unlock(&data->lock, key);

	while (!idma_retired(idma_read(dev, IDMA_DONE_ID), last_id)) {
	}

	key = k_spin_lock(&data->lock);
	chan->busy = false;
	k_spin_unlock(&data->lock, key);
	return 0;
}

static int idma_get_status(const struct device *dev, uint32_t channel, struct dma_status *stat)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	struct idma_channel *chan;
	k_spinlock_key_t key;
	uint32_t done_id;

	if (channel >= cfg->channels) {
		return -EINVAL;
	}

	chan = &data->channels[channel];
	*stat = (struct dma_status){.dir = MEMORY_TO_MEMORY};
	key = k_spin_lock(&data->lock);
	if (chan->busy) {
		done_id = idma_read(dev, IDMA_DONE_ID);
		for (uint32_t i = 0; i < chan->block_count; i++) {
			if (!idma_retired(done_id, chan->first_id + i)) {
				stat->pending_length += chan->blocks[i].len;
			}
		}
		stat->busy = stat->pending_length != 0U;
	}
	k_spin_unlock(&data->lock, key);
	return 0;
}

static int idma_get_attribute(const struct device *dev, uint32_t type, uint32_t *value)
{
	ARG_UNUSED(dev);

	switch (type) {
	case DMA_ATTR_BUFFER_ADDRESS_ALIGNMENT:
	case DMA_ATTR_BUFFER_SIZE_ALIGNMENT:
	case DMA_ATTR_COPY_ALIGNMENT:
		/* The iDMA handles any byte alignment and length. */
		*value = 1U;
		return 0;
	case DMA_ATTR_MAX_BLOCK_COUNT:
		*value = IDMA_MAX_BLOCKS;
		return 0;
	default:
		return -EINVAL;
	}
}

static void idma_isr(const struct device *dev)
{
	const struct idma_config *cfg = dev->config;
	struct idma_data *data = dev->data;
	uint32_t done_id;

	/* Clear the flag before reading DONE_ID: a copy that retires after the
	 * read sets the flag again and is picked up by the next interrupt. */
	idma_write(dev, IDMA_IRQ_STATUS, 1U);
	done_id = idma_read(dev, IDMA_DONE_ID);

	for (uint32_t c = 0; c < cfg->channels; c++) {
		struct idma_channel *chan = &data->channels[c];
		k_spinlock_key_t key = k_spin_lock(&data->lock);
		uint32_t from, to;
		bool complete, notify;
		dma_callback_t callback;
		void *user_data;

		if (!chan->busy || chan->stopping || !idma_retired(done_id, chan->reported_id + 1U)) {
			k_spin_unlock(&data->lock, key);
			continue;
		}
		/* Blocks from..to retired since the last report. */
		from = chan->reported_id + 1U;
		complete = idma_retired(done_id, chan->last_id);
		to = complete ? chan->last_id : done_id;
		chan->reported_id = to;
		if (complete) {
			chan->busy = false;
		}
		notify = chan->block_callbacks;
		callback = chan->callback;
		user_data = chan->user_data;
		k_spin_unlock(&data->lock, key);

		/* Callbacks run outside the lock, so they may start the next
		 * transfer. */
		if (callback == NULL) {
			continue;
		}
		if (notify) {
			for (uint32_t id = from; id != to; id++) {
				callback(dev, user_data, c, DMA_STATUS_BLOCK);
			}
		}
		if (complete) {
			callback(dev, user_data, c, DMA_STATUS_COMPLETE);
		} else if (notify) {
			callback(dev, user_data, c, DMA_STATUS_BLOCK);
		}
	}
}

static int idma_init(const struct device *dev)
{
	const struct idma_config *cfg = dev->config;

	/* A flag left over from before this boot would raise a spurious first
	 * interrupt. */
	idma_write(dev, IDMA_IRQ_STATUS, 1U);
	cfg->irq_configure();
	return 0;
}

static DEVICE_API(dma, idma_api) = {
	.config = idma_config,
	.reload = idma_reload,
	.start = idma_start,
	.stop = idma_stop,
	.get_status = idma_get_status,
	.get_attribute = idma_get_attribute,
};

#define IDMA_INIT(inst)                                                                            \
	static void idma_irq_configure_##inst(void)                                                \
	{                                                                                          \
		IRQ_CONNECT(DT_INST_IRQN(inst), DT_INST_IRQ(inst, priority), idma_isr,             \
			    DEVICE_DT_INST_GET(inst), 0);                                          \
		irq_enable(DT_INST_IRQN(inst));                                                    \
	}                                                                                          \
	static const struct idma_config idma_config_##inst = {                                     \
		.base = DT_INST_REG_ADDR(inst),                                                    \
		.channels = DT_INST_PROP(inst, dma_channels),                                      \
		.irq_configure = idma_irq_configure_##inst,                                        \
	};                                                                                         \
	static struct idma_channel idma_channels_##inst[DT_INST_PROP(inst, dma_channels)];         \
	ATOMIC_DEFINE(idma_atomic_##inst, DT_INST_PROP(inst, dma_channels));                       \
	static struct idma_data idma_data_##inst = {                                               \
		.ctx =                                                                             \
			{                                                                          \
				.magic = DMA_MAGIC,                                                \
				.atomic = idma_atomic_##inst,                                      \
				.dma_channels = DT_INST_PROP(inst, dma_channels),                  \
			},                                                                         \
		.channels = idma_channels_##inst,                                                  \
	};                                                                                         \
	DEVICE_DT_INST_DEFINE(inst, idma_init, NULL, &idma_data_##inst, &idma_config_##inst,       \
			      POST_KERNEL, CONFIG_DMA_INIT_PRIORITY, &idma_api);

DT_INST_FOREACH_STATUS_OKAY(IDMA_INIT)
