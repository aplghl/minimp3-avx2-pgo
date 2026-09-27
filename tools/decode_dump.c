/* Decode a whole MP3 buffer and dump raw PCM samples to stdout.
 * Used for bit-exact differential testing between two headers.
 * usage: decode_dump <file>
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MINIMP3_IMPLEMENTATION
#include "minimp3.h"

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
    int size = 0, left;
    uint8_t *buf;
    const uint8_t *p;
    mp3dec_t dec;
    mp3d_sample_t pcm[MINIMP3_MAX_SAMPLES_PER_FRAME];

    if (argc < 2)
        return 2;
    buf = read_file(argv[1], &size);
    if (!buf)
        return 2;

    mp3dec_init(&dec);
    p = buf;
    left = size;
    while (left > 4)
    {
        mp3dec_frame_info_t info;
        int samples = mp3dec_decode_frame(&dec, p, left, pcm, &info);
        if (info.frame_bytes <= 0)
            break;
        if (samples > 0)
        {
            size_t n = (size_t)samples * info.channels * sizeof(mp3d_sample_t);
            if (fwrite(pcm, 1, n, stdout) != n)
            {
                free(buf);
                return 3;
            }
        }
        p += info.frame_bytes;
        left -= info.frame_bytes;
    }
    free(buf);
    fflush(stdout);
    return 0;
}
