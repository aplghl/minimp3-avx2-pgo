/* Micro-benchmark for individual static kernels inside minimp3.h.
 * Include the implementation and call the static functions directly.
 *
 * usage: kernbench <dct2|synth|antialias|midside|imdct36> [budget] [repeats]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

#include <time.h>
static double now_sec(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static float grbuf[2*576 + 1024];
static float lins[4096];
static int16_t dst[1024];
static float ovl[2][9*32];
static const float win[2*9] = { 0 };

#define NSINK volatile float
static NSINK sink;

int main(int argc, char **argv)
{
    const char *k;
    double budget = 0.25, best = 1e30;
    int R = 7, r, i;
    long iters = 0, it;
    unsigned n = 0;

    if (argc < 2)
    {
        fprintf(stderr, "usage: %s <dct2|synth|antialias|midside|imdct36> [budget] [repeats]\n", argv[0]);
        return 2;
    }
    k = argv[1];
    if (argc > 2)
        budget = atof(argv[2]);
    if (argc > 3)
        R = atoi(argv[3]);

    for (i = 0; i < (int)(sizeof(grbuf)/sizeof(grbuf[0])); i++)
        grbuf[i] = (float)((i % 37) - 18) * 0.01f;
    for (i = 0; i < 4096; i++)
        lins[i] = (float)((i % 53) - 26) * 0.005f;

    /* warmup */
    for (i = 0; i < 1000; i++)
    {
        if (!strcmp(k, "dct2")) mp3d_DCT_II(grbuf, 18);
        else if (!strcmp(k, "synth")) mp3d_synth(grbuf, dst, 2, lins);
        else if (!strcmp(k, "antialias")) L3_antialias(grbuf, 31);
        else if (!strcmp(k, "midside")) L3_midside_stereo(grbuf, 576);
        else if (!strcmp(k, "imdct36")) L3_imdct36(grbuf, ovl[0], win, 18);
        else { fprintf(stderr, "unknown kernel %s\n", k); return 2; }
    }

    for (r = 0; r < R; r++)
    {
        double t0, t1, tcal0, dt, ns;
        double tcal = 0;
        (void)tcal;
        tcal0 = now_sec();
        for (i = 0; i < 1000; i++)
        {
            if (!strcmp(k, "dct2")) mp3d_DCT_II(grbuf, 18);
            else if (!strcmp(k, "synth")) mp3d_synth(grbuf, dst, 2, lins);
            else if (!strcmp(k, "antialias")) L3_antialias(grbuf, 31);
            else if (!strcmp(k, "midside")) L3_midside_stereo(grbuf, 576);
            else L3_imdct36(grbuf, ovl[0], win, 18);
        }
        dt = now_sec() - tcal0;
        iters = (long)(budget / (dt / 1000.0));
        if (iters < 1) iters = 1;
        if (iters > 100000000) iters = 100000000;
        n += (unsigned)iters;

        t0 = now_sec();
        for (it = 0; it < iters; it++)
        {
            if (!strcmp(k, "dct2")) mp3d_DCT_II(grbuf, 18);
            else if (!strcmp(k, "synth")) mp3d_synth(grbuf, dst, 2, lins);
            else if (!strcmp(k, "antialias")) L3_antialias(grbuf, 31);
            else if (!strcmp(k, "midside")) L3_midside_stereo(grbuf, 576);
            else L3_imdct36(grbuf, ovl[0], win, 18);
        }
        t1 = now_sec();
        ns = (t1 - t0) / (double)iters * 1e9;
        if (ns < best) best = ns;
    }
    sink = grbuf[0] + lins[0] + dst[0] + ovl[0][0];
    printf("%s,%.2f\n", k, best);
    return 0;
}
