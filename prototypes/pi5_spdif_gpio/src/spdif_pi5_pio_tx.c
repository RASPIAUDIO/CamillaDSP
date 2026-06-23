#define _POSIX_C_SOURCE 200809L

#include "spdif_bmc.h"

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile sig_atomic_t keep_running = 1;

static void handle_signal(int signal_number)
{
    (void)signal_number;
    keep_running = 0;
}

typedef struct {
    unsigned int gpio;
    uint32_t rate;
    uint32_t pio_clock_hz;
    const char *mode;
    const char *input_path;
    double tone;
    double sweep_start;
    double sweep_end;
    double seconds;
    double amplitude_dbfs;
    uint32_t chunk_frames;
    uint32_t dma_buffers;
} options_t;

typedef struct {
    uint32_t sample_rate;
    uint32_t data_offset;
    uint32_t data_bytes;
    uint32_t total_frames;
    uint16_t channels;
    uint16_t bits_per_sample;
    uint16_t block_align;
} wav_info_t;

static uint16_t read_u16le(const uint8_t bytes[2])
{
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8u);
}

static uint32_t read_u32le(const uint8_t bytes[4])
{
    return (uint32_t)bytes[0] |
           ((uint32_t)bytes[1] << 8u) |
           ((uint32_t)bytes[2] << 16u) |
           ((uint32_t)bytes[3] << 24u);
}

static int read_exact(FILE *file, void *buffer, size_t bytes)
{
    return fread(buffer, 1, bytes, file) == bytes ? 0 : -1;
}

static int skip_bytes(FILE *file, uint32_t bytes)
{
    return fseek(file, (long)(bytes + (bytes & 1u)), SEEK_CUR);
}

static int parse_wav_header(FILE *file, wav_info_t *info)
{
    uint8_t header[12];
    uint16_t audio_format = 0;
    uint32_t fmt_found = 0;
    uint32_t data_found = 0;

    memset(info, 0, sizeof(*info));

    if (read_exact(file, header, sizeof(header)) != 0 ||
        memcmp(header, "RIFF", 4) != 0 ||
        memcmp(header + 8, "WAVE", 4) != 0) {
        fprintf(stderr, "input is not a RIFF/WAVE file\n");
        return -1;
    }

    while (!data_found) {
        uint8_t chunk_header[8];
        uint32_t chunk_size;
        long chunk_data_offset;

        if (read_exact(file, chunk_header, sizeof(chunk_header)) != 0) {
            fprintf(stderr, "WAV header ended before data chunk\n");
            return -1;
        }

        chunk_size = read_u32le(chunk_header + 4);
        chunk_data_offset = ftell(file);
        if (chunk_data_offset < 0) {
            return -1;
        }

        if (memcmp(chunk_header, "fmt ", 4) == 0) {
            uint8_t fmt[16];
            if (chunk_size < sizeof(fmt) || read_exact(file, fmt, sizeof(fmt)) != 0) {
                fprintf(stderr, "unsupported or truncated WAV fmt chunk\n");
                return -1;
            }
            audio_format = read_u16le(fmt);
            info->channels = read_u16le(fmt + 2);
            info->sample_rate = read_u32le(fmt + 4);
            info->block_align = read_u16le(fmt + 12);
            info->bits_per_sample = read_u16le(fmt + 14);
            fmt_found = 1;

            if (fseek(file, chunk_data_offset + (long)(chunk_size + (chunk_size & 1u)), SEEK_SET) != 0) {
                return -1;
            }
        } else if (memcmp(chunk_header, "data", 4) == 0) {
            if (!fmt_found) {
                fprintf(stderr, "WAV data chunk appeared before fmt chunk\n");
                return -1;
            }
            info->data_offset = (uint32_t)chunk_data_offset;
            info->data_bytes = chunk_size;
            data_found = 1;
            if (fseek(file, chunk_data_offset + (long)(chunk_size + (chunk_size & 1u)), SEEK_SET) != 0) {
                return -1;
            }
        } else if (skip_bytes(file, chunk_size) != 0) {
            return -1;
        }
    }

    if (audio_format != 1 || info->channels != 2 || info->bits_per_sample != 16 || info->block_align != 4) {
        fprintf(stderr,
                "unsupported WAV format: audio_format=%u channels=%u bits=%u block_align=%u. Expected PCM s16le stereo.\n",
                audio_format,
                info->channels,
                info->bits_per_sample,
                info->block_align);
        return -1;
    }
    if (info->sample_rate == 0 || info->data_bytes < info->block_align) {
        fprintf(stderr, "invalid WAV data\n");
        return -1;
    }

    info->total_frames = info->data_bytes / info->block_align;
    return fseek(file, (long)info->data_offset, SEEK_SET);
}

static double monotonic_seconds(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) {
        return 0.0;
    }
    return (double)now.tv_sec + (double)now.tv_nsec / 1000000000.0;
}

static void sleep_seconds(double seconds)
{
    if (seconds <= 0.0) {
        return;
    }

    struct timespec req;
    req.tv_sec = (time_t)seconds;
    req.tv_nsec = (long)((seconds - (double)req.tv_sec) * 1000000000.0);
    while (nanosleep(&req, &req) != 0 && errno == EINTR) {
    }
}

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage: %s [--gpio 12] [--rate 48000] [--pio-clock-hz 200000000] [--mode tone|sweep|wav] [--input file.wav] [--tone 1000] [--sweep-start 120] [--sweep-end 6000] [--seconds 2] [--amplitude-dbfs -18] [--chunk-frames 0] [--dma-buffers 4]\n"
            "  The full finite stream is encoded first and submitted as one PIOLib transfer.\n"
            "  --chunk-frames 0 means roughly 0.5 second DMA bounce buffers inside that transfer.\n"
            "  --dma-buffers N sets the PIOLib DMA queue depth; default is 4.\n",
            argv0);
}

static int parse_options(int argc, char **argv, options_t *options)
{
    options->gpio = 12;
    options->rate = 48000;
    options->pio_clock_hz = 200000000;
    options->mode = "tone";
    options->input_path = NULL;
    options->tone = 1000.0;
    options->sweep_start = 120.0;
    options->sweep_end = 6000.0;
    options->seconds = 2.0;
    options->amplitude_dbfs = -18.0;
    options->chunk_frames = 0;
    options->dma_buffers = 4;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--gpio") == 0 && i + 1 < argc) {
            options->gpio = (unsigned int)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--rate") == 0 && i + 1 < argc) {
            options->rate = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--pio-clock-hz") == 0 && i + 1 < argc) {
            options->pio_clock_hz = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            options->mode = argv[++i];
        } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
            options->input_path = argv[++i];
        } else if (strcmp(argv[i], "--tone") == 0 && i + 1 < argc) {
            options->tone = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--sweep-start") == 0 && i + 1 < argc) {
            options->sweep_start = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--sweep-end") == 0 && i + 1 < argc) {
            options->sweep_end = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
            options->seconds = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--amplitude-dbfs") == 0 && i + 1 < argc) {
            options->amplitude_dbfs = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--chunk-frames") == 0 && i + 1 < argc) {
            options->chunk_frames = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--dma-buffers") == 0 && i + 1 < argc) {
            options->dma_buffers = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 1;
        } else {
            usage(argv[0]);
            return -1;
        }
    }

    if (options->rate == 0 || options->pio_clock_hz == 0 || options->seconds <= 0.0) {
        usage(argv[0]);
        return -1;
    }
    if (options->dma_buffers == 0 || options->dma_buffers > 16) {
        fprintf(stderr, "--dma-buffers must be between 1 and 16\n");
        return -1;
    }
    if (strcmp(options->mode, "tone") != 0 && strcmp(options->mode, "sweep") != 0 && strcmp(options->mode, "wav") != 0) {
        usage(argv[0]);
        return -1;
    }
    if (strcmp(options->mode, "wav") == 0 && options->input_path == NULL) {
        usage(argv[0]);
        return -1;
    }
    return 0;
}

#ifndef HAVE_PIOLIB
int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    fprintf(stderr, "spdif_pi5_pio_tx must be built with PIOLib support. Use: make pio PIOLIB_INC=... PIOLIB_LIB=...\n");
    return 2;
}
#else
#include "piolib.h"
#include "spdif_tx.pio.h"

int main(int argc, char **argv)
{
    options_t options;
    int parsed = parse_options(argc, argv, &options);
    if (parsed != 0) {
        return parsed > 0 ? 0 : 2;
    }

    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);

    FILE *wav_file = NULL;
    wav_info_t wav_info;
    int wav_mode = strcmp(options.mode, "wav") == 0;
    if (wav_mode) {
        wav_file = fopen(options.input_path, "rb");
        if (!wav_file) {
            fprintf(stderr, "cannot open WAV input %s: %s\n", options.input_path, strerror(errno));
            return 1;
        }
        if (parse_wav_header(wav_file, &wav_info) != 0) {
            fclose(wav_file);
            return 1;
        }
        options.rate = wav_info.sample_rate;
    }

    uint32_t total_frames = wav_mode ? wav_info.total_frames : (uint32_t)(options.seconds * (double)options.rate + 0.5);
    if (total_frames == 0) {
        fprintf(stderr, "nothing to play\n");
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    uint32_t dma_buffer_frames = options.chunk_frames;
    if (dma_buffer_frames == 0) {
        dma_buffer_frames = options.rate / 2u;
        if (dma_buffer_frames == 0) {
            dma_buffer_frames = options.rate;
        }
    }

    size_t dma_buffer_words = spdif_packed_word_count_for_frames(dma_buffer_frames);
    size_t dma_buffer_bytes = dma_buffer_words * sizeof(uint32_t);
    if (dma_buffer_bytes == 0 || dma_buffer_bytes > UINT_MAX) {
        fprintf(stderr, "invalid DMA buffer size: %zu bytes\n", dma_buffer_bytes);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    size_t transfer_word_capacity = spdif_packed_word_count_for_frames(total_frames);
    size_t transfer_capacity_bytes = transfer_word_capacity * sizeof(uint32_t);
    if (transfer_capacity_bytes == 0 || transfer_capacity_bytes > UINT_MAX) {
        fprintf(stderr,
                "encoded transfer would be %zu bytes; split the file or build a kernel/cyclic-DMA path for this length\n",
                transfer_capacity_bytes);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    uint32_t *transfer_words = calloc(transfer_word_capacity, sizeof(uint32_t));
    if (!transfer_words) {
        fprintf(stderr, "allocation failed for %zu bytes\n", transfer_capacity_bytes);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    int16_t *pcm_chunk = NULL;
    if (wav_mode) {
        pcm_chunk = calloc((size_t)dma_buffer_frames * 2u, sizeof(int16_t));
        if (!pcm_chunk) {
            fprintf(stderr, "allocation failed for PCM chunk\n");
            free(transfer_words);
            fclose(wav_file);
            return 1;
        }
    }

    printf("Pi 5 RP1/PIO S/PDIF experimental TX\n");
    printf("GPIO %u, PCM %u Hz, S/PDIF half-bit clock %u Hz, PIO clock %u Hz, mode %s\n",
           options.gpio,
           options.rate,
           spdif_halfbit_rate(options.rate),
           options.pio_clock_hz,
           options.mode);
    printf("DMA bounce buffer %u frames/%zu bytes, queued buffers %u, full transfer %u frames/%zu bytes\n",
           dma_buffer_frames,
           dma_buffer_bytes,
           options.dma_buffers,
           total_frames,
           transfer_capacity_bytes);
    if (wav_mode) {
        printf("WAV input %s, %u frames, %.2f seconds\n",
               options.input_path,
               total_frames,
               (double)total_frames / (double)options.rate);
    }
    printf("Pre-encoding finite stream into one PIOLib transfer to avoid inter-block FIFO underruns.\n");

    spdif_bmc_state_t state;
    spdif_bmc_state_init(&state, options.rate);

    uint32_t frames_encoded = 0;
    size_t words_encoded = 0;
    double encode_start = monotonic_seconds();
    while (keep_running && frames_encoded < total_frames) {
        uint32_t frames_this_chunk = dma_buffer_frames;
        if (total_frames - frames_encoded < frames_this_chunk) {
            frames_this_chunk = total_frames - frames_encoded;
        }

        size_t words = 0;
        size_t remaining_words = transfer_word_capacity - words_encoded;
        if (wav_mode) {
            size_t frames_read = fread(pcm_chunk, wav_info.block_align, frames_this_chunk, wav_file);
            if (frames_read == 0) {
                break;
            }
            frames_this_chunk = (uint32_t)frames_read;
            words = spdif_bmc_encode_pcm_s16le_24(&state,
                                                  pcm_chunk,
                                                  frames_this_chunk,
                                                  transfer_words + words_encoded,
                                                  remaining_words);
        } else if (strcmp(options.mode, "sweep") == 0) {
            words = spdif_bmc_encode_sweep_24(&state,
                                              options.sweep_start,
                                              options.sweep_end,
                                              options.amplitude_dbfs,
                                              frames_this_chunk,
                                              total_frames,
                                              transfer_words + words_encoded,
                                              remaining_words);
        } else {
            words = spdif_bmc_encode_sine_24(&state,
                                             options.tone,
                                             options.amplitude_dbfs,
                                             frames_this_chunk,
                                             transfer_words + words_encoded,
                                             remaining_words);
        }

        if (words == 0) {
            fprintf(stderr, "encoder produced no data\n");
            free(pcm_chunk);
            free(transfer_words);
            if (wav_file) {
                fclose(wav_file);
            }
            return 1;
        }

        frames_encoded += frames_this_chunk;
        words_encoded += words;
    }

    if (frames_encoded == 0 || words_encoded == 0) {
        fprintf(stderr, "no encoded data to transmit\n");
        free(pcm_chunk);
        free(transfer_words);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    size_t transfer_bytes = words_encoded * sizeof(uint32_t);
    double encode_elapsed = monotonic_seconds() - encode_start;
    printf("Encoded %u stereo frames into %zu bytes in %.3fs.\n",
           frames_encoded,
           transfer_bytes,
           encode_elapsed);

    PIO pio = pio0;
    if (PIO_IS_ERR(pio)) {
        fprintf(stderr, "cannot open pio0; check /dev/pio0, kernel, EEPROM, and gpio group permissions\n");
        free(pcm_chunk);
        free(transfer_words);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    int sm = pio_claim_unused_sm(pio, true);
    uint offset = pio_add_program(pio, &spdif_tx_program);
    pio_sm_config_xfer(pio, (uint)sm, PIO_DIR_TO_SM, (uint)dma_buffer_bytes, options.dma_buffers);
    pio_sm_clear_fifos(pio, (uint)sm);
    spdif_tx_program_init(pio, (uint)sm, offset, options.gpio, (float)spdif_halfbit_rate(options.rate), options.pio_clock_hz);

    printf("Submitting one contiguous transfer. Output is raw GPIO for lab testing only. Stop with Ctrl+C.\n");
    double transfer_start = monotonic_seconds();
    int ret = pio_sm_xfer_data(pio, (uint)sm, PIO_DIR_TO_SM, (uint)transfer_bytes, transfer_words);
    double transfer_elapsed = monotonic_seconds() - transfer_start;
    int transfer_ok = ret == 0;
    if (!transfer_ok) {
        fprintf(stderr, "pio_sm_xfer_data failed: %s\n", strerror(errno));
    } else {
        sleep_seconds(0.10);
    }

    pio_sm_set_enabled(pio, (uint)sm, false);
    pio_sm_unclaim(pio, (uint)sm);
    pio_remove_program(pio, &spdif_tx_program, offset);
    pio_close(pio);
    free(pcm_chunk);
    free(transfer_words);
    if (wav_file) {
        fclose(wav_file);
    }

    printf("Done, sent %u/%u stereo frames in one transfer. Transfer call %.3fs for %.3fs of audio.\n",
           frames_encoded,
           total_frames,
           transfer_elapsed,
           (double)frames_encoded / (double)options.rate);
    return transfer_ok && frames_encoded == total_frames ? 0 : 1;
}
#endif
