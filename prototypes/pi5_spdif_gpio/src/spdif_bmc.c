#include "spdif_bmc.h"

#include <math.h>
#include <stdbool.h>
#include <string.h>

#define SPDIF_PREAMBLE_M 0xE2u
#define SPDIF_PREAMBLE_W 0xE4u
#define SPDIF_PREAMBLE_B 0xE8u

static void put_halfbit(spdif_word_packer_t *packer, uint8_t bit)
{
    if (packer->word_count >= packer->word_capacity) {
        return;
    }

    if (bit) {
        packer->word |= 1u << (31u - packer->used_bits);
    }

    packer->used_bits++;
    if (packer->used_bits == 32u) {
        packer->words[packer->word_count++] = packer->word;
        packer->word = 0;
        packer->used_bits = 0;
    }
}

static void put_preamble(spdif_word_packer_t *packer, uint8_t preamble, uint8_t *last_level)
{
    uint8_t symbol = *last_level ? (uint8_t)~preamble : preamble;

    for (int bit = 7; bit >= 0; --bit) {
        put_halfbit(packer, (uint8_t)((symbol >> bit) & 1u));
    }
    *last_level = (uint8_t)(symbol & 1u);
}

static void put_bmc_data_bit(spdif_word_packer_t *packer, uint8_t data_bit, uint8_t *last_level)
{
    uint8_t first = (uint8_t)(!*last_level);
    uint8_t second = data_bit ? (uint8_t)(!first) : first;

    put_halfbit(packer, first);
    put_halfbit(packer, second);
    *last_level = second;
}

static uint8_t get_channel_status_bit(const uint8_t status[24], uint32_t frame_index)
{
    return (uint8_t)((status[frame_index / 8u] >> (frame_index % 8u)) & 1u);
}

static uint32_t sample_to_24_bits(int32_t sample)
{
    if (sample > 8388607) {
        sample = 8388607;
    } else if (sample < -8388608) {
        sample = -8388608;
    }

    return ((uint32_t)sample) & 0x00ffffffu;
}

static int encode_subframe(spdif_word_packer_t *packer,
                           uint8_t preamble,
                           int32_t sample_24,
                           uint8_t channel_status_bit,
                           uint8_t *last_level)
{
    uint8_t data_bits[28];
    uint32_t sample = sample_to_24_bits(sample_24);
    uint8_t parity = 0;
    size_t index = 0;

    if (packer->word_count >= packer->word_capacity) {
        return -1;
    }

    put_preamble(packer, preamble, last_level);

    for (uint8_t bit = 0; bit < 24u; ++bit) {
        data_bits[index++] = (uint8_t)((sample >> bit) & 1u);
    }

    data_bits[index++] = 0;                  /* Validity: 0 means linear PCM sample is valid. */
    data_bits[index++] = 0;                  /* User bit: unused in this prototype. */
    data_bits[index++] = channel_status_bit; /* One channel-status bit per subframe. */

    for (size_t bit = 0; bit < index; ++bit) {
        parity ^= data_bits[bit];
    }
    data_bits[index++] = parity; /* Makes the 28 transmitted data bits even parity. */

    for (size_t bit = 0; bit < index; ++bit) {
        put_bmc_data_bit(packer, data_bits[bit], last_level);
    }

    return packer->word_count <= packer->word_capacity ? 0 : -1;
}

void spdif_bmc_state_init(spdif_bmc_state_t *state, uint32_t sample_rate)
{
    memset(state, 0, sizeof(*state));
    state->sample_rate = sample_rate;

    state->channel_status_l[0] = 0x04; /* Consumer PCM, not copyright asserted. */
    state->channel_status_r[0] = 0x04;
    state->channel_status_l[2] = 0x10; /* Left channel number. */
    state->channel_status_r[2] = 0x20; /* Right channel number. */

    switch (sample_rate) {
    case 32000:
        state->channel_status_l[3] = 0x03;
        state->channel_status_r[3] = 0x03;
        break;
    case 44100:
        state->channel_status_l[3] = 0x00;
        state->channel_status_r[3] = 0x00;
        break;
    case 48000:
        state->channel_status_l[3] = 0x02;
        state->channel_status_r[3] = 0x02;
        break;
    case 96000:
        state->channel_status_l[3] = 0x0a;
        state->channel_status_r[3] = 0x0a;
        break;
    default:
        state->channel_status_l[3] = 0x01; /* Not indicated. */
        state->channel_status_r[3] = 0x01;
        break;
    }
}

void spdif_word_packer_init(spdif_word_packer_t *packer, uint32_t *words, size_t word_capacity)
{
    memset(packer, 0, sizeof(*packer));
    packer->words = words;
    packer->word_capacity = word_capacity;
}

int spdif_word_packer_flush(spdif_word_packer_t *packer)
{
    if (packer->used_bits == 0) {
        return 0;
    }
    if (packer->word_count >= packer->word_capacity) {
        return -1;
    }
    packer->words[packer->word_count++] = packer->word;
    packer->word = 0;
    packer->used_bits = 0;
    return 0;
}

int spdif_bmc_encode_stereo_frame(spdif_bmc_state_t *state,
                                  int32_t left_sample_24,
                                  int32_t right_sample_24,
                                  spdif_word_packer_t *packer)
{
    uint32_t frame_in_block = state->sample_index % SPDIF_FRAMES_PER_BLOCK;
    uint8_t left_preamble = frame_in_block == 0 ? SPDIF_PREAMBLE_B : SPDIF_PREAMBLE_M;
    uint8_t left_status = get_channel_status_bit(state->channel_status_l, frame_in_block);
    uint8_t right_status = get_channel_status_bit(state->channel_status_r, frame_in_block);

    if (encode_subframe(packer, left_preamble, left_sample_24, left_status, &state->bmc_level) != 0) {
        return -1;
    }
    if (encode_subframe(packer, SPDIF_PREAMBLE_W, right_sample_24, right_status, &state->bmc_level) != 0) {
        return -1;
    }

    state->sample_index++;
    return 0;
}

size_t spdif_bmc_encode_sine_24(spdif_bmc_state_t *state,
                                double tone_hz,
                                double amplitude_dbfs,
                                uint32_t frames,
                                uint32_t *words,
                                size_t word_capacity)
{
    spdif_word_packer_t packer;
    const double pi = 3.14159265358979323846;
    double amplitude = pow(10.0, amplitude_dbfs / 20.0) * 8388607.0;

    spdif_word_packer_init(&packer, words, word_capacity);

    for (uint32_t frame = 0; frame < frames; ++frame) {
        double phase = 2.0 * pi * tone_hz * (double)(state->sample_index) / (double)state->sample_rate;
        int32_t sample = (int32_t)lrint(sin(phase) * amplitude);
        if (spdif_bmc_encode_stereo_frame(state, sample, sample, &packer) != 0) {
            break;
        }
    }

    if (spdif_word_packer_flush(&packer) != 0) {
        return 0;
    }
    return packer.word_count;
}

uint32_t spdif_halfbit_rate(uint32_t sample_rate)
{
    return sample_rate * SPDIF_HALFBITS_PER_STEREO_FRAME;
}

size_t spdif_packed_word_count_for_frames(uint32_t frames)
{
    return ((size_t)frames * SPDIF_HALFBITS_PER_STEREO_FRAME + 31u) / 32u;
}

size_t spdif_packed_byte_count_for_frames(uint32_t frames)
{
    return spdif_packed_word_count_for_frames(frames) * sizeof(uint32_t);
}
