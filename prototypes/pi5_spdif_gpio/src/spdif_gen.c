#include "spdif_bmc.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t rate;
    double tone;
    double seconds;
    double amplitude_dbfs;
    const char *output_path;
    int self_test;
} options_t;

static void usage(const char *argv0)
{
    fprintf(stderr,
            "Usage: %s [--rate 48000] [--tone 1000] [--seconds 1] [--amplitude-dbfs -12] --output out.bmc32 [--self-test]\n",
            argv0);
}

static int parse_options(int argc, char **argv, options_t *options)
{
    options->rate = 48000;
    options->tone = 1000.0;
    options->seconds = 1.0;
    options->amplitude_dbfs = -12.0;
    options->output_path = NULL;
    options->self_test = 0;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--rate") == 0 && i + 1 < argc) {
            options->rate = (uint32_t)strtoul(argv[++i], NULL, 0);
        } else if (strcmp(argv[i], "--tone") == 0 && i + 1 < argc) {
            options->tone = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--seconds") == 0 && i + 1 < argc) {
            options->seconds = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--amplitude-dbfs") == 0 && i + 1 < argc) {
            options->amplitude_dbfs = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
            options->output_path = argv[++i];
        } else if (strcmp(argv[i], "--self-test") == 0) {
            options->self_test = 1;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 1;
        } else {
            usage(argv[0]);
            return -1;
        }
    }

    if (!options->output_path) {
        usage(argv[0]);
        return -1;
    }
    if (options->rate == 0 || options->seconds <= 0.0 || options->tone < 0.0) {
        usage(argv[0]);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    options_t options;
    int parsed = parse_options(argc, argv, &options);
    if (parsed != 0) {
        return parsed > 0 ? 0 : 2;
    }

    uint32_t frames = (uint32_t)(options.seconds * (double)options.rate + 0.5);
    size_t word_count = spdif_packed_word_count_for_frames(frames);
    size_t byte_count = word_count * sizeof(uint32_t);
    uint32_t *words = calloc(word_count, sizeof(uint32_t));
    if (!words) {
        fprintf(stderr, "allocation failed for %zu bytes\n", byte_count);
        return 1;
    }

    spdif_bmc_state_t state;
    spdif_bmc_state_init(&state, options.rate);
    size_t written_words = spdif_bmc_encode_sine_24(&state,
                                                    options.tone,
                                                    options.amplitude_dbfs,
                                                    frames,
                                                    words,
                                                    word_count);
    if (written_words != word_count) {
        fprintf(stderr, "encoder stopped early: %zu/%zu words\n", written_words, word_count);
        free(words);
        return 1;
    }

    FILE *output = fopen(options.output_path, "wb");
    if (!output) {
        fprintf(stderr, "cannot open %s: %s\n", options.output_path, strerror(errno));
        free(words);
        return 1;
    }

    if (fwrite(words, sizeof(uint32_t), written_words, output) != written_words) {
        fprintf(stderr, "write failed for %s\n", options.output_path);
        fclose(output);
        free(words);
        return 1;
    }
    fclose(output);

    printf("Wrote %s\n", options.output_path);
    printf("PCM: %u Hz stereo, %.3f s, %.1f Hz sine, %.1f dBFS\n",
           options.rate,
           options.seconds,
           options.tone,
           options.amplitude_dbfs);
    printf("S/PDIF half-bit clock: %u Hz\n", spdif_halfbit_rate(options.rate));
    printf("Payload: %u stereo frames, %zu packed 32-bit words, %zu bytes\n",
           frames,
           written_words,
           byte_count);

    if (options.self_test) {
        size_t expected_48k_1s = 48000u * SPDIF_BYTES_PER_STEREO_FRAME;
        if (options.rate == 48000u && frames == 48000u && byte_count != expected_48k_1s) {
            fprintf(stderr, "self-test failed: got %zu bytes, expected %zu\n", byte_count, expected_48k_1s);
            free(words);
            return 1;
        }
        printf("Self-test: OK\n");
    }

    free(words);
    return 0;
}
