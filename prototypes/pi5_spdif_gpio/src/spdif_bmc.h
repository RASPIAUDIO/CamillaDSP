#ifndef RASPIAUDIO_SPDIF_BMC_H
#define RASPIAUDIO_SPDIF_BMC_H

#include <stddef.h>
#include <stdint.h>

#define SPDIF_FRAMES_PER_BLOCK 192u
#define SPDIF_HALFBITS_PER_STEREO_FRAME 128u
#define SPDIF_BYTES_PER_STEREO_FRAME (SPDIF_HALFBITS_PER_STEREO_FRAME / 8u)

typedef struct {
    uint32_t sample_rate;
    uint32_t sample_index;
    uint8_t channel_status_l[24];
    uint8_t channel_status_r[24];
} spdif_bmc_state_t;

typedef struct {
    uint32_t word;
    uint8_t used_bits;
    uint32_t *words;
    size_t word_capacity;
    size_t word_count;
} spdif_word_packer_t;

void spdif_bmc_state_init(spdif_bmc_state_t *state, uint32_t sample_rate);

void spdif_word_packer_init(spdif_word_packer_t *packer, uint32_t *words, size_t word_capacity);
int spdif_word_packer_flush(spdif_word_packer_t *packer);

int spdif_bmc_encode_stereo_frame(spdif_bmc_state_t *state,
                                  int32_t left_sample_24,
                                  int32_t right_sample_24,
                                  spdif_word_packer_t *packer);

size_t spdif_bmc_encode_sine_24(spdif_bmc_state_t *state,
                                double tone_hz,
                                double amplitude_dbfs,
                                uint32_t frames,
                                uint32_t *words,
                                size_t word_capacity);

uint32_t spdif_halfbit_rate(uint32_t sample_rate);
size_t spdif_packed_word_count_for_frames(uint32_t frames);
size_t spdif_packed_byte_count_for_frames(uint32_t frames);

#endif
