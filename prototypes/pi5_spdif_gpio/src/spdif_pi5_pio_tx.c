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
    double tone;
    double sweep_start;
    double sweep_end;
    double seconds;
    double amplitude_dbfs;
    uint32_t chunk_frames;
} options_t;

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
            "Usage: %s [--gpio 12] [--rate 48000] [--pio-clock-hz 100000000] [--mode tone|sweep] [--tone 1000] [--sweep-start 120] [--sweep-end 6000] [--seconds 2] [--amplitude-dbfs -18] [--chunk-frames 0]\n"
            "  --chunk-frames 0 precomputes the full test tone and sends it as one DMA transfer.\n"
            "  Keep one-shot tests short; transfers above about 2 seconds can hit the current PIOLib timeout.\n",
            argv0);
}

static int parse_options(int argc, char **argv, options_t *options)
{
    options->gpio = 12;
    options->rate = 48000;
    options->pio_clock_hz = 100000000;
    options->mode = "tone";
    options->tone = 1000.0;
    options->sweep_start = 120.0;
    options->sweep_end = 6000.0;
    options->seconds = 2.0;
    options->amplitude_dbfs = -18.0;
    options->chunk_frames = 0;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--gpio") == 0 && i + 1 < argc) {
            options->gpio = (unsigned int)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--rate") == 0 && i + 1 < argc) {
            options->rate = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--pio-clock-hz") == 0 && i + 1 < argc) {
            options->pio_clock_hz = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            options->mode = argv[++i];
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
    if (strcmp(options->mode, "tone") != 0 && strcmp(options->mode, "sweep") != 0) {
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

    uint32_t total_frames = (uint32_t)(options.seconds * (double)options.rate + 0.5);
    uint32_t effective_chunk_frames = options.chunk_frames == 0 ? total_frames : options.chunk_frames;

    size_t chunk_words = spdif_packed_word_count_for_frames(effective_chunk_frames);
    size_t chunk_bytes = chunk_words * sizeof(uint32_t);
    uint32_t *chunk = calloc(chunk_words, sizeof(uint32_t));
    if (!chunk) {
        fprintf(stderr, "allocation failed for %zu bytes\n", chunk_bytes);
        return 1;
    }

    PIO pio = pio0;
    if (PIO_IS_ERR(pio)) {
        fprintf(stderr, "cannot open pio0; check /dev/pio0, kernel, EEPROM, and gpio group permissions\n");
        free(chunk);
        return 1;
    }

    int sm = pio_claim_unused_sm(pio, true);
    uint offset = pio_add_program(pio, &spdif_tx_program);
    pio_sm_config_xfer(pio, (uint)sm, PIO_DIR_TO_SM, (uint)chunk_bytes, 4);
    pio_sm_clear_fifos(pio, (uint)sm);
    spdif_tx_program_init(pio, (uint)sm, offset, options.gpio, (float)spdif_halfbit_rate(options.rate), options.pio_clock_hz);

    printf("Pi 5 RP1/PIO S/PDIF experimental TX\n");
    printf("GPIO %u, PCM %u Hz, S/PDIF half-bit clock %u Hz, PIO clock %u Hz, mode %s, chunk %u frames/%zu bytes\n",
           options.gpio,
           options.rate,
           spdif_halfbit_rate(options.rate),
           options.pio_clock_hz,
           options.mode,
           effective_chunk_frames,
           chunk_bytes);
    if (options.chunk_frames == 0) {
        printf("Using one-shot DMA test mode to avoid inter-chunk underruns.\n");
    }
    printf("Output is raw GPIO for lab testing only. Stop with Ctrl+C.\n");

    spdif_bmc_state_t state;
    spdif_bmc_state_init(&state, options.rate);

    uint32_t frames_sent = 0;

    while (keep_running && frames_sent < total_frames) {
        uint32_t frames_this_chunk = effective_chunk_frames;
        if (total_frames - frames_sent < frames_this_chunk) {
            frames_this_chunk = total_frames - frames_sent;
        }

        memset(chunk, 0, chunk_bytes);
        size_t words = 0;
        if (strcmp(options.mode, "sweep") == 0) {
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
        if (ret != 0) {
            fprintf(stderr, "pio_sm_xfer_data failed: %s\n", strerror(errno));
            break;
        }
        if (options.chunk_frames == 0) {
            double elapsed = monotonic_seconds() - transfer_start;
            double expected = (double)frames_this_chunk / (double)options.rate;
            sleep_seconds(expected - elapsed + 0.05);
        }

        frames_sent += frames_this_chunk;
    }

    pio_sm_set_enabled(pio, (uint)sm, false);
    pio_sm_unclaim(pio, (uint)sm);
    pio_remove_program(pio, &spdif_tx_program, offset);
    pio_close(pio);
    free(chunk);

    printf("Done, sent %u stereo frames.\n", frames_sent);
    return frames_sent == total_frames ? 0 : 1;
}
#endif
