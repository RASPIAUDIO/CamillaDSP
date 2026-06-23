// SPDX-License-Identifier: GPL-2.0
/*
 * Experimental Raspberry Pi 5 RP1/PIO S/PDIF ALSA playback driver.
 *
 * V1 is intentionally fixed at 48 kHz, stereo, S16_LE/S32_LE. It uses the
 * Raspberry Pi rp1-pio kernel API and re-arms one 20 ms DMA period at a time.
 */

#include <linux/err.h>
#include <linux/init.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pio_rp1.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/wait.h>

#include <sound/core.h>
#include <sound/initval.h>
#include <sound/memalloc.h>
#include <sound/pcm.h>
#include <sound/pcm_params.h>

#define DRIVER_NAME "raspiaudio_spdif_pio"
#define CARD_ID "RASPISPDIF"
#define PCM_NAME "Raspberry Pi 5 RP1 PIO S/PDIF"

#define SPDIF_RATE 48000u
#define SPDIF_CHANNELS 2u
#define SPDIF_FRAMES_PER_BLOCK 192u
#define SPDIF_HALFBITS_PER_STEREO_FRAME 128u
#define SPDIF_BYTES_PER_STEREO_FRAME (SPDIF_HALFBITS_PER_STEREO_FRAME / 8u)
#define SPDIF_HALFBIT_RATE (SPDIF_RATE * SPDIF_HALFBITS_PER_STEREO_FRAME)

#define SPDIF_PERIOD_FRAMES 960u
#define SPDIF_BUFFER_PERIODS 4u
#define SPDIF_BUFFER_FRAMES (SPDIF_PERIOD_FRAMES * SPDIF_BUFFER_PERIODS)
#define SPDIF_PERIOD_WORDS \
	((SPDIF_PERIOD_FRAMES * SPDIF_HALFBITS_PER_STEREO_FRAME) / 32u)
#define SPDIF_PERIOD_BYTES (SPDIF_PERIOD_WORDS * sizeof(u32))
#define SPDIF_MAX_PCM_BUFFER_BYTES (SPDIF_BUFFER_FRAMES * SPDIF_CHANNELS * sizeof(s32))

#define SPDIF_PREAMBLE_M 0xe2u
#define SPDIF_PREAMBLE_W 0xe4u
#define SPDIF_PREAMBLE_B 0xe8u

static unsigned int gpio = 12;
module_param(gpio, uint, 0444);
MODULE_PARM_DESC(gpio, "RP1 GPIO used for raw S/PDIF output, default 12");

static unsigned int drive_ma = 8;
module_param(drive_ma, uint, 0444);
MODULE_PARM_DESC(drive_ma, "RP1 GPIO drive strength in mA: 2, 4, 8 or 12");

static bool zero_on_underrun = true;
module_param(zero_on_underrun, bool, 0644);
MODULE_PARM_DESC(zero_on_underrun, "Transmit silence when ALSA has no complete period ready");

struct spdif_bmc_state {
	u32 sample_index;
	u8 bmc_level;
	u8 channel_status_l[24];
	u8 channel_status_r[24];
};

struct spdif_word_packer {
	u32 word;
	u8 used_bits;
	u32 *words;
	size_t word_capacity;
	size_t word_count;
	bool overflow;
};

struct raspiaudio_spdif {
	struct snd_card *card;
	struct snd_pcm *pcm;
	struct snd_pcm_substream *substream;

	PIO pio;
	int sm;
	u32 offset;
	bool pio_ready;
	bool pio_enabled;
	bool sm_claimed;
	bool program_loaded;

	spinlock_t lock;
	struct mutex ops_lock;
	wait_queue_head_t wait;
	struct task_struct *feeder;

	bool running;
	bool stopping;
	unsigned int queued;
	unsigned int elapsed;
	unsigned int next_slot;
	u64 hw_pos;
	snd_pcm_uframes_t submit_pos;
	snd_pcm_format_t format;

	u32 *encoded;
	struct spdif_bmc_state bmc;
	unsigned int underruns;
	unsigned int dma_errors;
};

static struct raspiaudio_spdif *g_chip;
static struct platform_device *g_pdev;

static const u16 spdif_tx_program_instructions[] = {
	0x6001, /* out pins, 1 */
};

static const struct pio_program spdif_tx_program = {
	.instructions = spdif_tx_program_instructions,
	.length = 1,
	.origin = -1,
};

static const struct snd_pcm_hardware spdif_pcm_hw = {
	.info = SNDRV_PCM_INFO_INTERLEAVED |
		SNDRV_PCM_INFO_BLOCK_TRANSFER |
		SNDRV_PCM_INFO_BATCH,
	.formats = SNDRV_PCM_FMTBIT_S16_LE | SNDRV_PCM_FMTBIT_S32_LE,
	.rates = SNDRV_PCM_RATE_48000,
	.rate_min = SPDIF_RATE,
	.rate_max = SPDIF_RATE,
	.channels_min = SPDIF_CHANNELS,
	.channels_max = SPDIF_CHANNELS,
	.buffer_bytes_max = SPDIF_MAX_PCM_BUFFER_BYTES,
	.period_bytes_min = SPDIF_PERIOD_FRAMES * SPDIF_CHANNELS * sizeof(s16),
	.period_bytes_max = SPDIF_PERIOD_FRAMES * SPDIF_CHANNELS * sizeof(s32),
	.periods_min = SPDIF_BUFFER_PERIODS,
	.periods_max = SPDIF_BUFFER_PERIODS,
	.fifo_size = 0,
};

static void spdif_bmc_state_init(struct spdif_bmc_state *state)
{
	memset(state, 0, sizeof(*state));
	state->channel_status_l[0] = 0x04; /* Consumer PCM, not copyright asserted. */
	state->channel_status_r[0] = 0x04;
	state->channel_status_l[2] = 0x10; /* Left channel number. */
	state->channel_status_r[2] = 0x20; /* Right channel number. */
	state->channel_status_l[3] = 0x02; /* 48 kHz. */
	state->channel_status_r[3] = 0x02;
}

static void spdif_word_packer_init(struct spdif_word_packer *packer,
				   u32 *words, size_t word_capacity)
{
	memset(packer, 0, sizeof(*packer));
	packer->words = words;
	packer->word_capacity = word_capacity;
}

static void spdif_put_halfbit(struct spdif_word_packer *packer, u8 bit)
{
	if (packer->word_count >= packer->word_capacity) {
		packer->overflow = true;
		return;
	}

	if (bit)
		packer->word |= 1u << (31u - packer->used_bits);

	packer->used_bits++;
	if (packer->used_bits == 32u) {
		packer->words[packer->word_count++] = packer->word;
		packer->word = 0;
		packer->used_bits = 0;
	}
}

static void spdif_put_preamble(struct spdif_word_packer *packer,
			       u8 preamble, u8 *last_level)
{
	u8 symbol = *last_level ? (u8)~preamble : preamble;
	int bit;

	for (bit = 7; bit >= 0; bit--)
		spdif_put_halfbit(packer, (symbol >> bit) & 1u);
	*last_level = symbol & 1u;
}

static void spdif_put_bmc_data_bit(struct spdif_word_packer *packer,
				   u8 data_bit, u8 *last_level)
{
	u8 first = !*last_level;
	u8 second = data_bit ? !first : first;

	spdif_put_halfbit(packer, first);
	spdif_put_halfbit(packer, second);
	*last_level = second;
}

static u8 spdif_channel_status_bit(const u8 status[24], u32 frame_index)
{
	return (status[frame_index / 8u] >> (frame_index % 8u)) & 1u;
}

static u32 spdif_sample_to_24_bits(s32 sample)
{
	if (sample > 8388607)
		sample = 8388607;
	else if (sample < -8388608)
		sample = -8388608;

	return (u32)sample & 0x00ffffffu;
}

static int spdif_encode_subframe(struct spdif_word_packer *packer,
				 u8 preamble, s32 sample_24,
				 u8 channel_status_bit, u8 *last_level)
{
	u8 data_bits[28];
	u32 sample = spdif_sample_to_24_bits(sample_24);
	u8 parity = 0;
	size_t index = 0;
	size_t bit;

	spdif_put_preamble(packer, preamble, last_level);

	for (bit = 0; bit < 24u; bit++)
		data_bits[index++] = (sample >> bit) & 1u;

	data_bits[index++] = 0; /* Valid linear PCM sample. */
	data_bits[index++] = 0; /* User bit unused. */
	data_bits[index++] = channel_status_bit;

	for (bit = 0; bit < index; bit++)
		parity ^= data_bits[bit];
	data_bits[index++] = parity;

	for (bit = 0; bit < index; bit++)
		spdif_put_bmc_data_bit(packer, data_bits[bit], last_level);

	return packer->overflow ? -ENOSPC : 0;
}

static int spdif_encode_stereo_frame(struct spdif_bmc_state *state,
				     s32 left_sample_24, s32 right_sample_24,
				     struct spdif_word_packer *packer)
{
	u32 frame_in_block = state->sample_index % SPDIF_FRAMES_PER_BLOCK;
	u8 left_preamble = frame_in_block == 0 ? SPDIF_PREAMBLE_B : SPDIF_PREAMBLE_M;
	u8 left_status = spdif_channel_status_bit(state->channel_status_l, frame_in_block);
	u8 right_status = spdif_channel_status_bit(state->channel_status_r, frame_in_block);
	int ret;

	ret = spdif_encode_subframe(packer, left_preamble, left_sample_24,
				    left_status, &state->bmc_level);
	if (ret)
		return ret;

	ret = spdif_encode_subframe(packer, SPDIF_PREAMBLE_W, right_sample_24,
				    right_status, &state->bmc_level);
	if (ret)
		return ret;

	state->sample_index++;
	return 0;
}

static bool spdif_period_has_data(struct raspiaudio_spdif *chip,
				  struct snd_pcm_runtime *runtime)
{
	snd_pcm_sframes_t ready;
	unsigned int queued;

	ready = snd_pcm_playback_hw_avail(runtime);
	spin_lock_irq(&chip->lock);
	queued = chip->queued;
	spin_unlock_irq(&chip->lock);

	return ready >= (snd_pcm_sframes_t)((queued + 1u) * SPDIF_PERIOD_FRAMES);
}

static int spdif_encode_period(struct raspiaudio_spdif *chip, u32 *dst)
{
	struct snd_pcm_substream *substream = chip->substream;
	struct snd_pcm_runtime *runtime;
	struct spdif_word_packer packer;
	bool have_data;
	u32 frame;
	int ret;

	memset(dst, 0, SPDIF_PERIOD_BYTES);

	if (!substream || !substream->runtime)
		have_data = false;
	else
		have_data = spdif_period_has_data(chip, substream->runtime);

	if (!have_data) {
		if (!zero_on_underrun)
			return -EPIPE;
		chip->underruns++;
	}

	runtime = substream ? substream->runtime : NULL;
	spdif_word_packer_init(&packer, dst, SPDIF_PERIOD_WORDS);

	for (frame = 0; frame < SPDIF_PERIOD_FRAMES; frame++) {
		s32 left = 0;
		s32 right = 0;

		if (have_data && runtime && runtime->dma_area) {
			snd_pcm_uframes_t pos = (chip->submit_pos + frame) %
						runtime->buffer_size;
			u8 *base = runtime->dma_area + frames_to_bytes(runtime, pos);

			if (chip->format == SNDRV_PCM_FORMAT_S16_LE) {
				s16 *samples = (s16 *)base;

				left = (s32)samples[0] << 8;
				right = (s32)samples[1] << 8;
			} else if (chip->format == SNDRV_PCM_FORMAT_S32_LE) {
				s32 *samples = (s32 *)base;

				left = samples[0] >> 8;
				right = samples[1] >> 8;
			}
		}

		ret = spdif_encode_stereo_frame(&chip->bmc, left, right, &packer);
		if (ret)
			return ret;
	}

	if (packer.word_count != SPDIF_PERIOD_WORDS || packer.used_bits)
		return -EIO;

	return 0;
}

static bool spdif_is_running(struct raspiaudio_spdif *chip)
{
	bool running;

	spin_lock_irq(&chip->lock);
	running = chip->running;
	spin_unlock_irq(&chip->lock);

	return running;
}

static int spdif_set_pio_enabled(struct raspiaudio_spdif *chip, bool enabled)
{
	int ret;

	if (!chip->pio_ready)
		return -ENODEV;

	ret = pio_sm_set_enabled(chip->pio, chip->sm, enabled);
	if (ret)
		return ret;

	spin_lock_irq(&chip->lock);
	chip->pio_enabled = enabled;
	spin_unlock_irq(&chip->lock);
	wake_up(&chip->wait);
	return 0;
}

static void spdif_dma_done(void *param)
{
	struct raspiaudio_spdif *chip = param;

	spin_lock(&chip->lock);
	if (chip->queued)
		chip->queued--;
	chip->hw_pos += SPDIF_PERIOD_FRAMES;
	if (chip->running && chip->substream)
		chip->elapsed++;
	spin_unlock(&chip->lock);

	wake_up(&chip->wait);
}

static void spdif_report_elapsed(struct raspiaudio_spdif *chip)
{
	for (;;) {
		struct snd_pcm_substream *substream;

		spin_lock_irq(&chip->lock);
		if (!chip->elapsed || !chip->substream) {
			spin_unlock_irq(&chip->lock);
			break;
		}
		chip->elapsed--;
		substream = chip->substream;
		spin_unlock_irq(&chip->lock);

		snd_pcm_period_elapsed(substream);
	}
}

static int spdif_submit_next_period(struct raspiaudio_spdif *chip)
{
	u32 slot;
	u32 *period;
	bool running;
	int ret;

	spin_lock_irq(&chip->lock);
	running = chip->running;
	slot = chip->next_slot % SPDIF_BUFFER_PERIODS;
	spin_unlock_irq(&chip->lock);

	if (!running)
		return 0;

	period = chip->encoded + (slot * SPDIF_PERIOD_WORDS);
	ret = spdif_encode_period(chip, period);
	if (ret)
		return ret;

	if (!spdif_is_running(chip))
		return 0;

	ret = pio_sm_xfer_data(chip->pio, chip->sm, PIO_DIR_TO_SM,
			       SPDIF_PERIOD_BYTES, period, 0, spdif_dma_done,
			       chip);
	if (ret)
		return ret;

	spin_lock_irq(&chip->lock);
	chip->queued++;
	chip->next_slot++;
	if (chip->substream && chip->substream->runtime)
		chip->submit_pos = (chip->submit_pos + SPDIF_PERIOD_FRAMES) %
				   chip->substream->runtime->buffer_size;
	spin_unlock_irq(&chip->lock);

	return 0;
}

static int spdif_feeder_thread(void *data)
{
	struct raspiaudio_spdif *chip = data;

	while (!kthread_should_stop()) {
		wait_event_interruptible(chip->wait,
					 kthread_should_stop() ||
					 chip->elapsed ||
					 (spdif_is_running(chip) &&
					  chip->queued < SPDIF_BUFFER_PERIODS));

		spdif_report_elapsed(chip);

		while (!kthread_should_stop() && spdif_is_running(chip)) {
			bool should_enable;
			int ret;

			spin_lock_irq(&chip->lock);
			if (chip->queued >= SPDIF_BUFFER_PERIODS) {
				spin_unlock_irq(&chip->lock);
				break;
			}
			spin_unlock_irq(&chip->lock);

			ret = spdif_submit_next_period(chip);
			if (ret) {
				spin_lock_irq(&chip->lock);
				chip->dma_errors++;
				chip->running = false;
				spin_unlock_irq(&chip->lock);
				wake_up(&chip->wait);
				break;
			}

			spin_lock_irq(&chip->lock);
			should_enable = chip->running && !chip->pio_enabled &&
					chip->queued >= SPDIF_BUFFER_PERIODS;
			spin_unlock_irq(&chip->lock);

			if (should_enable) {
				ret = spdif_set_pio_enabled(chip, true);
				if (ret) {
					spin_lock_irq(&chip->lock);
					chip->dma_errors++;
					chip->running = false;
					spin_unlock_irq(&chip->lock);
					wake_up(&chip->wait);
					break;
				}
			}

			spdif_report_elapsed(chip);
		}
	}

	return 0;
}

static void spdif_reset_stream_state(struct raspiaudio_spdif *chip,
				     struct snd_pcm_runtime *runtime)
{
	spin_lock_irq(&chip->lock);
	chip->running = false;
	chip->stopping = false;
	chip->queued = 0;
	chip->elapsed = 0;
	chip->next_slot = 0;
	chip->hw_pos = 0;
	chip->submit_pos = 0;
	chip->format = runtime->format;
	chip->underruns = 0;
	chip->dma_errors = 0;
	spin_unlock_irq(&chip->lock);

	spdif_bmc_state_init(&chip->bmc);
}

static int spdif_stop_locked(struct raspiaudio_spdif *chip)
{
	unsigned long deadline = jiffies + msecs_to_jiffies(500);
	int ret = 0;

	spin_lock_irq(&chip->lock);
	chip->running = false;
	chip->stopping = true;
	spin_unlock_irq(&chip->lock);
	wake_up(&chip->wait);

	while (time_before(jiffies, deadline)) {
		bool queued;
		bool enabled;

		spin_lock_irq(&chip->lock);
		queued = chip->queued != 0;
		enabled = chip->pio_enabled;
		spin_unlock_irq(&chip->lock);

		if (!queued)
			break;

		if (!enabled) {
			ret = spdif_set_pio_enabled(chip, true);
			if (ret)
				break;
		}

		wait_event_timeout(chip->wait, chip->queued == 0,
				   msecs_to_jiffies(20));
	}

	spin_lock_irq(&chip->lock);
	if (chip->queued)
		ret = ret ?: -ETIMEDOUT;
	spin_unlock_irq(&chip->lock);

	if (chip->pio_enabled)
		spdif_set_pio_enabled(chip, false);

	if (chip->pio_ready) {
		pio_sm_drain_tx_fifo(chip->pio, chip->sm);
		pio_sm_clear_fifos(chip->pio, chip->sm);
		pio_sm_restart(chip->pio, chip->sm);
	}

	spin_lock_irq(&chip->lock);
	chip->stopping = false;
	spin_unlock_irq(&chip->lock);

	return ret;
}

static int spdif_start_locked(struct raspiaudio_spdif *chip,
			      struct snd_pcm_substream *substream)
{
	int ret;

	ret = spdif_stop_locked(chip);
	if (ret)
		return ret;

	if (!chip->pio_ready)
		return -ENODEV;

	spdif_reset_stream_state(chip, substream->runtime);

	pio_sm_set_enabled(chip->pio, chip->sm, false);
	pio_sm_drain_tx_fifo(chip->pio, chip->sm);
	pio_sm_clear_fifos(chip->pio, chip->sm);
	pio_sm_restart(chip->pio, chip->sm);
	pio_sm_clkdiv_restart(chip->pio, chip->sm);

	spin_lock_irq(&chip->lock);
	chip->running = true;
	chip->pio_enabled = false;
	spin_unlock_irq(&chip->lock);
	wake_up(&chip->wait);

	if (!wait_event_timeout(chip->wait,
				chip->pio_enabled || !spdif_is_running(chip),
				msecs_to_jiffies(500))) {
		spin_lock_irq(&chip->lock);
		chip->running = false;
		spin_unlock_irq(&chip->lock);
		wake_up(&chip->wait);
		return -ETIMEDOUT;
	}

	return spdif_is_running(chip) ? 0 : -EIO;
}

static int spdif_pcm_open(struct snd_pcm_substream *substream)
{
	struct raspiaudio_spdif *chip = snd_pcm_substream_chip(substream);
	struct snd_pcm_runtime *runtime = substream->runtime;
	int ret;

	mutex_lock(&chip->ops_lock);
	if (chip->substream && chip->substream != substream) {
		mutex_unlock(&chip->ops_lock);
		return -EBUSY;
	}
	chip->substream = substream;
	mutex_unlock(&chip->ops_lock);

	runtime->hw = spdif_pcm_hw;
	ret = snd_pcm_hw_constraint_single(runtime, SNDRV_PCM_HW_PARAM_RATE,
					   SPDIF_RATE);
	if (ret < 0)
		return ret;
	ret = snd_pcm_hw_constraint_single(runtime, SNDRV_PCM_HW_PARAM_CHANNELS,
					   SPDIF_CHANNELS);
	if (ret < 0)
		return ret;
	ret = snd_pcm_hw_constraint_single(runtime,
					   SNDRV_PCM_HW_PARAM_PERIOD_SIZE,
					   SPDIF_PERIOD_FRAMES);
	if (ret < 0)
		return ret;
	ret = snd_pcm_hw_constraint_single(runtime,
					   SNDRV_PCM_HW_PARAM_BUFFER_SIZE,
					   SPDIF_BUFFER_FRAMES);
	if (ret < 0)
		return ret;
	return snd_pcm_hw_constraint_integer(runtime, SNDRV_PCM_HW_PARAM_PERIODS);
}

static int spdif_pcm_close(struct snd_pcm_substream *substream)
{
	struct raspiaudio_spdif *chip = snd_pcm_substream_chip(substream);

	mutex_lock(&chip->ops_lock);
	spdif_stop_locked(chip);
	chip->substream = NULL;
	mutex_unlock(&chip->ops_lock);
	return 0;
}

static int spdif_pcm_hw_params(struct snd_pcm_substream *substream,
			       struct snd_pcm_hw_params *params)
{
	return snd_pcm_lib_malloc_pages(substream, params_buffer_bytes(params));
}

static int spdif_pcm_hw_free(struct snd_pcm_substream *substream)
{
	return snd_pcm_lib_free_pages(substream);
}

static int spdif_pcm_prepare(struct snd_pcm_substream *substream)
{
	struct raspiaudio_spdif *chip = snd_pcm_substream_chip(substream);

	mutex_lock(&chip->ops_lock);
	if (spdif_is_running(chip)) {
		mutex_unlock(&chip->ops_lock);
		return -EBUSY;
	}
	spdif_reset_stream_state(chip, substream->runtime);
	mutex_unlock(&chip->ops_lock);
	return 0;
}

static int spdif_pcm_trigger(struct snd_pcm_substream *substream, int cmd)
{
	struct raspiaudio_spdif *chip = snd_pcm_substream_chip(substream);
	int ret;

	mutex_lock(&chip->ops_lock);
	switch (cmd) {
	case SNDRV_PCM_TRIGGER_START:
	case SNDRV_PCM_TRIGGER_RESUME:
	case SNDRV_PCM_TRIGGER_PAUSE_RELEASE:
		ret = spdif_start_locked(chip, substream);
		break;
	case SNDRV_PCM_TRIGGER_STOP:
	case SNDRV_PCM_TRIGGER_SUSPEND:
	case SNDRV_PCM_TRIGGER_PAUSE_PUSH:
		ret = spdif_stop_locked(chip);
		break;
	default:
		ret = -EINVAL;
		break;
	}
	mutex_unlock(&chip->ops_lock);
	return ret;
}

static snd_pcm_uframes_t spdif_pcm_pointer(struct snd_pcm_substream *substream)
{
	struct raspiaudio_spdif *chip = snd_pcm_substream_chip(substream);
	snd_pcm_uframes_t pos;

	spin_lock(&chip->lock);
	pos = chip->hw_pos % SPDIF_BUFFER_FRAMES;
	spin_unlock(&chip->lock);
	return pos;
}

static const struct snd_pcm_ops spdif_pcm_ops = {
	.open = spdif_pcm_open,
	.close = spdif_pcm_close,
	.ioctl = snd_pcm_lib_ioctl,
	.hw_params = spdif_pcm_hw_params,
	.hw_free = spdif_pcm_hw_free,
	.prepare = spdif_pcm_prepare,
	.trigger = spdif_pcm_trigger,
	.pointer = spdif_pcm_pointer,
};

static enum gpio_drive_strength spdif_drive_strength(unsigned int ma)
{
	switch (ma) {
	case 2:
		return GPIO_DRIVE_STRENGTH_2MA;
	case 4:
		return GPIO_DRIVE_STRENGTH_4MA;
	case 12:
		return GPIO_DRIVE_STRENGTH_12MA;
	case 8:
	default:
		return GPIO_DRIVE_STRENGTH_8MA;
	}
}

static int spdif_pio_setup(struct raspiaudio_spdif *chip)
{
	pio_sm_config config;
	struct fp24_8 div;
	int ret;

	if (gpio >= 18 && gpio <= 27)
		return -EINVAL;

	chip->pio = pio_open();
	if (IS_ERR(chip->pio))
		return PTR_ERR(chip->pio);

	chip->sm = pio_claim_unused_sm(chip->pio, true);
	if (chip->sm < 0) {
		ret = chip->sm;
		goto err_close;
	}
	chip->sm_claimed = true;

	chip->offset = pio_add_program(chip->pio, &spdif_tx_program);
	if (chip->offset == PIO_ORIGIN_ANY) {
		ret = -ENOSPC;
		goto err_close;
	}
	chip->program_loaded = true;

	ret = pio_sm_config_xfer(chip->pio, chip->sm, PIO_DIR_TO_SM,
				 SPDIF_PERIOD_BYTES, SPDIF_BUFFER_PERIODS);
	if (ret)
		goto err_close;

	ret = pio_gpio_init(chip->pio, gpio);
	if (ret)
		goto err_close;
	pio_gpio_disable_pulls(chip->pio, gpio);
	pio_gpio_set_drive_strength(chip->pio, gpio,
				    spdif_drive_strength(drive_ma));

	ret = pio_sm_set_consecutive_pindirs(chip->pio, chip->sm, gpio, 1,
					     true);
	if (ret)
		goto err_close;

	config = pio_get_default_sm_config();
	sm_config_set_wrap(&config, chip->offset, chip->offset);
	sm_config_set_out_pins(&config, gpio, 1);
	sm_config_set_out_shift(&config, false, true, 32);
	sm_config_set_fifo_join(&config, PIO_FIFO_JOIN_TX);
	div = make_fp24_8(clock_get_hz(clk_sys), SPDIF_HALFBIT_RATE);
	sm_config_set_clkdiv(&config, div);

	ret = pio_sm_init(chip->pio, chip->sm, chip->offset, &config);
	if (ret)
		goto err_close;

	pio_sm_set_enabled(chip->pio, chip->sm, false);
	pio_sm_clear_fifos(chip->pio, chip->sm);
	chip->pio_ready = true;
	return 0;

err_close:
	if (chip->pio && !IS_ERR(chip->pio)) {
		if (chip->program_loaded) {
			pio_remove_program(chip->pio, &spdif_tx_program,
					   chip->offset);
			chip->program_loaded = false;
			chip->offset = PIO_ORIGIN_ANY;
		}
		if (chip->sm_claimed) {
			pio_sm_unclaim(chip->pio, chip->sm);
			chip->sm_claimed = false;
			chip->sm = -1;
		}
		pio_close(chip->pio);
		chip->pio = NULL;
	}
	return ret;
}

static void spdif_pio_cleanup(struct raspiaudio_spdif *chip)
{
	if (!chip->pio || IS_ERR(chip->pio))
		return;

	spdif_stop_locked(chip);
	chip->pio_ready = false;
	if (chip->program_loaded) {
		pio_remove_program(chip->pio, &spdif_tx_program, chip->offset);
		chip->program_loaded = false;
		chip->offset = PIO_ORIGIN_ANY;
	}
	if (chip->sm_claimed) {
		pio_sm_unclaim(chip->pio, chip->sm);
		chip->sm_claimed = false;
		chip->sm = -1;
	}
	pio_close(chip->pio);
	chip->pio = NULL;
}

static int spdif_create_card(struct device *dev, struct raspiaudio_spdif **chip_ret)
{
	struct snd_card *card;
	struct raspiaudio_spdif *chip;
	struct snd_pcm *pcm;
	int ret;

	ret = snd_card_new(dev, -1, CARD_ID, THIS_MODULE, sizeof(*chip), &card);
	if (ret < 0)
		return ret;

	chip = card->private_data;
	chip->card = card;
	chip->sm = -1;
	chip->offset = PIO_ORIGIN_ANY;
	spin_lock_init(&chip->lock);
	mutex_init(&chip->ops_lock);
	init_waitqueue_head(&chip->wait);

	chip->encoded = kcalloc(SPDIF_BUFFER_PERIODS, SPDIF_PERIOD_BYTES,
				GFP_KERNEL);
	if (!chip->encoded) {
		ret = -ENOMEM;
		goto err_card;
	}

	ret = spdif_pio_setup(chip);
	if (ret)
		goto err_encoded;

	chip->feeder = kthread_run(spdif_feeder_thread, chip,
				   "raspiaudio_spdif");
	if (IS_ERR(chip->feeder)) {
		ret = PTR_ERR(chip->feeder);
		chip->feeder = NULL;
		goto err_pio;
	}

	ret = snd_pcm_new(card, "RASPISPDIF PCM", 0, 1, 0, &pcm);
	if (ret < 0)
		goto err_thread;

	chip->pcm = pcm;
	pcm->private_data = chip;
	pcm->nonatomic = true;
	strscpy(pcm->name, PCM_NAME, sizeof(pcm->name));
	snd_pcm_set_ops(pcm, SNDRV_PCM_STREAM_PLAYBACK, &spdif_pcm_ops);
	snd_pcm_set_managed_buffer_all(pcm, SNDRV_DMA_TYPE_VMALLOC, NULL,
				       SPDIF_MAX_PCM_BUFFER_BYTES,
				       SPDIF_MAX_PCM_BUFFER_BYTES);

	strscpy(card->driver, DRIVER_NAME, sizeof(card->driver));
	strscpy(card->shortname, "RASPIAUDIO S/PDIF PIO",
		sizeof(card->shortname));
	snprintf(card->longname, sizeof(card->longname),
		 "RASPIAUDIO Pi5 RP1 PIO S/PDIF on GPIO%u", gpio);

	ret = snd_card_register(card);
	if (ret < 0)
		goto err_thread;

	*chip_ret = chip;
	return 0;

err_thread:
	if (chip->feeder)
		kthread_stop(chip->feeder);
err_pio:
	spdif_pio_cleanup(chip);
err_encoded:
	kfree(chip->encoded);
err_card:
	snd_card_free(card);
	return ret;
}

static int __init spdif_module_init(void)
{
	int ret;

	g_pdev = platform_device_register_simple(DRIVER_NAME, -1, NULL, 0);
	if (IS_ERR(g_pdev))
		return PTR_ERR(g_pdev);

	ret = spdif_create_card(&g_pdev->dev, &g_chip);
	if (ret) {
		platform_device_unregister(g_pdev);
		g_pdev = NULL;
		return ret;
	}

	pr_info(DRIVER_NAME ": registered %s on GPIO%u, 48 kHz stereo only\n",
		CARD_ID, gpio);
	return 0;
}

static void __exit spdif_module_exit(void)
{
	struct raspiaudio_spdif *chip = g_chip;

	if (!chip)
		return;

	if (chip->feeder)
		kthread_stop(chip->feeder);
	spdif_pio_cleanup(chip);
	kfree(chip->encoded);
	snd_card_free(chip->card);
	g_chip = NULL;
	if (g_pdev) {
		platform_device_unregister(g_pdev);
		g_pdev = NULL;
	}
}

module_init(spdif_module_init);
module_exit(spdif_module_exit);

MODULE_AUTHOR("RASPIAUDIO");
MODULE_DESCRIPTION("Experimental Raspberry Pi 5 RP1 PIO S/PDIF ALSA playback driver");
MODULE_LICENSE("GPL");
