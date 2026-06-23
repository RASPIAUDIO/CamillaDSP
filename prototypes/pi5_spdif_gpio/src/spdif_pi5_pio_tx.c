#define _POSIX_C_SOURCE 200809L

#include "spdif_bmc.h"

#include <errno.h>
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
            "  --chunk-frames 0 precomputes the full test tone and sends it as one DMA transfer.\n"
            "  For --mode wav, --chunk-frames 0 means roughly 0.5 second chunks fed into the PIOLib DMA queue.\n"
            "  --dma-buffers N sets the PIOLib DMA queue depth for streaming modes; default is 4.\n"
            "  Keep one-shot tests short; transfers above about 2 seconds can hit the current PIOLib timeout.\n",
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
    int one_shot_mode = !wav_mode && options.chunk_frames == 0;
    uint32_t effective_chunk_frames = one_shot_mode ? total_frames : options.chunk_frames;
    if (effective_chunk_frames == 0) {
        effective_chunk_frames = options.rate / 2u;
        if (effective_chunk_frames == 0) {
            effective_chunk_frames = options.rate;
        }
    }

    size_t chunk_words = spdif_packed_word_count_for_frames(effective_chunk_frames);
    size_t chunk_bytes = chunk_words * sizeof(uint32_t);
    uint32_t *chunk = calloc(chunk_words, sizeof(uint32_t));
    if (!chunk) {
        fprintf(stderr, "allocation failed for %zu bytes\n", chunk_bytes);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    int16_t *pcm_chunk = NULL;
    if (wav_mode) {
        pcm_chunk = calloc((size_t)effective_chunk_frames * 2u, sizeof(int16_t));
        if (!pcm_chunk) {
            fprintf(stderr, "allocation failed for PCM chunk\n");
            free(chunk);
            fclose(wav_file);
            return 1;
        }
    }

    PIO pio = pio0;
    if (PIO_IS_ERR(pio)) {
        fprintf(stderr, "cannot open pio0; check /dev/pio0, kernel, EEPROM, and gpio group permissions\n");
        free(pcm_chunk);
        free(chunk);
        if (wav_file) {
            fclose(wav_file);
        }
        return 1;
    }

    int sm = pio_claim_unused_sm(pio, true);
    uint offset = pio_add_program(pio, &spdif_tx_program);
    pio_sm_config_xfer(pio, (uint)sm, PIO_DIR_TO_SM, (uint)chunk_bytes, options.dma_buffers);
    pio_sm_clear_fifos(pio, (uint)sm);
    spdif_tx_program_init(pio, (uint)sm, offset, options.gpio, (float)spdif_halfbit_rate(options.rate), options.pio_clock_hz);

    printf("Pi 5 RP1/PIO S/PDIF experimental TX\n");
    printf("GPIO %u, PCM %u Hz, S/PDIF half-bit clock %u Hz, PIO clock %u Hz, mode %s, chunk %u frames/%zu bytes, DMA buffers %u\n",
           options.gpio,
           options.rate,
           spdif_halfbit_rate(options.rate),
           options.pio_clock_hz,
           options.mode,
           effective_chunk_frames,
           chunk_bytes,
           options.dma_buffers);
    if (wav_mode) {
        printf("WAV input %s, %u frames, %.2f seconds\n",
               options.input_path,
               total_frames,
               (double)total_frames / (double)options.rate);
    }
    if (one_shot_mode) {
        printf("Using one-shot DMA test mode to avoid inter-chunk underruns.\n");
    } else {
        printf("Using queued PIOLib DMA streaming mode.\n");
    }
    printf("Output is raw GPIO for lab testing only. Stop with Ctrl+C.\n");

    spdif_bmc_state_t state;
    spdif_bmc_state_init(&state, options.rate);

    uint32_t frames_sent = 0;
    uint32_t chunks_sent = 0;
    uint32_t slow_xfers = 0;
    double max_xfer_seconds = 0.0;
    double total_xfer_seconds = 0.0;
    double stream_start = monotonic_seconds();

    while (keep_running && frames_sent < total_frames) {
        uint32_t frames_this_chunk = effective_chunk_frames;
        if (total_frames - frames_sent < frames_this_chunk) {
            frames_this_chunk = total_frames - frames_sent;
        }

        memset(chunk, 0, chunk_bytes);
        size_t words = 0;
        if (wav_mode) {
            size_t frames_read = fread(pcm_chunk, wav_info.block_align, frames_this_chunk, wav_file);
            if (frames_read == 0) {
                break;
            }
            frames_this_chunk = (uint32_t)frames_read;
            words = spdif_bmc_encode_pcm_s16le_24(&state,
                                                  pcm_chunk,
                                                  frames_this_chunk,
                                                  chunk,
                                                  chunk_words);
        } else if (strcmp(options.mode, "sweep") == 0) {
            words = spdif_bmc_encode_sweep_24(&state,
                                              options.sweep_start,
                                              options.sweep_end,
                                              options.amplitude_dbfs,
                                              frames_this_chunk,
                                              total_frames,
                                              chunk,
                                              chunk_words);
        } else {
            words = spdif_bmc_encode_sine_24(&state,
                                             options.tone,
                                             options.amplitude_dbfs,
                                             frames_this_chunk,
                                             chunk,
                                             chunk_words);
        }
        if (words == 0) {
            fprintf(stderr, "encoder produced no data\n");
            break;
        }

        double transfer_start = monotonic_seconds();
        int ret = pio_sm_xfer_data(pio, (uint)sm, PIO_DIR_TO_SM, (uint)(words * sizeof(uint32_t)), chunk);
        double elapsed = monotonic_seconds() - transfer_start;
        if (ret != 0) {
            fprintf(stderr, "pio_sm_xfer_data failed: %s\n", strerror(errno));
            break;
        }
        chunks_sent++;
        total_xfer_seconds += elapsed;
        if (elapsed > max_xfer_seconds) {
            max_xfer_seconds = elapsed;
        }
        if (one_shot_mode) {
            double expected = (double)frames_this_chunk / (double)options.rate;
            sleep_seconds(expected - elapsed + 0.05);
        } else {
            double expected = (double)frames_this_chunk / (double)options.rate;
            if (elapsed > expected * 1.10) {
                slow_xfers++;
                fprintf(stderr,
                        "warning: DMA queue call took %.3fs for a %.3fs chunk; possible underrun/backpressure\n",
                        elapsed,
                        expected);
            }
        }

        frames_sent += frames_this_chunk;
    }

    if (!one_shot_mode && frames_sent > 0) {
        double expected_stream_seconds = (double)frames_sent / (double)options.rate;
        double queued_elapsed = monotonic_seconds() - stream_start;
        double drain_seconds = expected_stream_seconds - queued_elapsed + 0.25;
        if (drain_seconds < 0.10) {
            drain_seconds = 0.10;
        }
        printf("Queued data in %.3fs for %.3fs of audio; waiting %.3fs before stopping PIO.\n",
               queued_elapsed,
               expected_stream_seconds,
               drain_seconds);
        sleep_seconds(drain_seconds);
    }

    pio_sm_set_enabled(pio, (uint)sm, false);
    pio_sm_unclaim(pio, (uint)sm);
    pio_remove_program(pio, &spdif_tx_program, offset);
    pio_close(pio);
    free(pcm_chunk);
    free(chunk);
    if (wav_file) {
        fclose(wav_file);
    }

    printf("Done, sent %u stereo frames in %u DMA chunks. Max xfer call %.3fs, avg %.3fs, slow calls %u.\n",
           frames_sent,
           chunks_sent,
           max_xfer_seconds,
           chunks_sent ? total_xfer_seconds / (double)chunks_sent : 0.0,
           slow_xfers);
    return frames_sent == total_frames ? 0 : 1;
}
#endif
