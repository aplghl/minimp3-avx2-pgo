/* minimp3 benchmark harness.
 *
 * Compile with:
 *   gcc -O2 bench/bench.c -I<dir with minimp3.h> -lm -o bench/bench
 * Header selection is via -I<dir> (upstream/ = baseline oracle, src/ = candidate).
 *
 * Measures full-buffer decode throughput via the low level frame API,
 * which is what the codec hot paths actually execute. Reports ns/sample
 * and TSC cycles/sample using min-of-R repeats to reject noise.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

#if defined(__x86_64__) || defined(__i386__)
static inline uint64_t tsc(void)
{
    unsigned lo, hi;
    __asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t)hi << 32) | lo;
}
#else
static inline uint64_t tsc(void) { return 0; }
#endif

#include <time.h>
static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static long decode_all(const uint8_t *buf, int size, mp3d_sample_t *pcm)
{
    mp3dec_t dec;
    const uint8_t *p = buf;
    int left = size;
    long total = 0;
    mp3dec_init(&dec);
    while (left > 4)
    {
        mp3dec_frame_info_t info;
        int samples = mp3dec_decode_frame(&dec, p, left, pcm, &info);
        if (info.frame_bytes <= 0)
            break;
        p += info.frame_bytes;
        left -= info.frame_bytes;
        if (samples > 0)
            total += (long)samples * info.channels;
    }
    return total;
}

static uint8_t *read_file(const char *path, int *out_size)
{
    FILE *f = fopen(path, "rb");
    uint8_t *buf;
    long size;
    if (!f)
        return NULL;
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = (uint8_t *)malloc((size_t)size);
    if (!buf || fread(buf, 1, (size_t)size, f) != (size_t)size)
    {
        free(buf);
        fclose(f);
        return NULL;
    }
    fclose(f);
    *out_size = (int)size;
    return buf;
}

int main(int argc, char **argv)
{
    int size = 0, warm;
    uint8_t *buf;
    mp3d_sample_t *pcm;
    long samples;
    double budget = 0.25, best_ns = 1e30, best_cyc = 1e30;
    int r, R = 7;
    long iters = 0, it;

    if (argc < 2)
    {
        fprintf(stderr, "usage: %s <file.mp3|bit> [budget_seconds] [repeats]\n", argv[0]);
        return 2;
    }
    if (argc > 2)
        budget = atof(argv[2]);
    if (argc > 3)
        R = atoi(argv[3]);

    buf = read_file(argv[1], &size);
    if (!buf)
    {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 2;
    }
    pcm = (mp3d_sample_t *)malloc(sizeof(mp3d_sample_t) * MINIMP3_MAX_SAMPLES_PER_FRAME);
    if (!pcm)
        return 2;

    for (warm = 0; warm < 3; warm++)
        samples = decode_all(buf, size, pcm);
    if (samples <= 0)
    {
        fprintf(stderr, "no samples decoded from %s\n", argv[1]);
        free(buf);
        free(pcm);
        return 2;
    }

    for (r = 0; r < R; r++)
    {
        double t0, t1, cyc0, cyc1, ns, cyc;
        uint64_t c0, c1;
        /* calibrate iteration count for this repeat to hit ~budget seconds */
        double tcal0 = now_sec();
        decode_all(buf, size, pcm);
        double dt = now_sec() - tcal0;
        iters = (long)(budget / (dt > 1e-9 ? dt : 1e-9));
        if (iters < 1)
            iters = 1;
        if (iters > 100000)
            iters = 100000;

        t0 = now_sec();
        c0 = tsc();
        for (it = 0; it < iters; it++)
            decode_all(buf, size, pcm);
        c1 = tsc();
        t1 = now_sec();

        ns = (t1 - t0) / ((double)iters * (double)samples) * 1e9;
        cyc = (double)(c1 - c0) / ((double)iters * (double)samples);
        if (ns < best_ns)
            best_ns = ns;
        if (cyc < best_cyc)
            best_cyc = cyc;
    }

    printf("%s,%d,%ld,%ld,%.3f,%.3f,%.2f\n",
           argv[1], size, samples, iters, best_ns, best_cyc,
           samples / (best_ns * 1e-9) / 1e6);

    free(buf);
    free(pcm);
    return 0;
}
