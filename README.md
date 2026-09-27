# minimp3-avx2

An AVX2-optimized fork of [minimp3](https://github.com/lieff/minimp3) (single
header MP3 decoder), plus a reproducible PGO build recipe and a differential
correctness/benchmark harness.

- **Upstream base:** `lieff/minimp3` at commit
  [`ea99364`](https://github.com/lieff/minimp3/tree/ea99364f61c14656440e8d77e9c233ccf3124633)
  (tracked as the `upstream/` submodule).
- **License:** CC0-1.0, same as upstream. See `LICENSE`.

> Developed with AI assistance. Every change is verified by the included
> bit-exact differential harness and the upstream conformance suite; see
> `NOTES.md` for the method, results, and rejected experiments.

## Results

Decoding throughput over a 14-vector suite, geometric mean against stock
upstream `-O2` (Intel i7-14700F; gcc 13.3; see `NOTES.md` for the full table):

| build | mean ns/sample | throughput vs upstream |
| ----- | -------------- | ---------------------- |
| upstream `-O2` | 5.830 | baseline |
| this fork, **exact** (AVX2 + PGO) | 3.492 | **+71%** |
| this fork, **fast** (`-ffast-math`, FMA) | 3.430 | **+74.5%** |

The exact build is **bit-identical** to upstream on all 89 test vectors.

## What changed

All changes live in `src/minimp3.h` and are gated behind
`#if defined(__AVX2__)`, following the existing SSE/NEON pattern, so the
generic and SSE paths are untouched:

- `mp3d_DCT_II` — 8-wide AVX2 transform (SSE tail).
- `mp3d_synth` — two filter phases per 256-bit iteration, plus packed stereo
  output stores.
- `L3_antialias`, `L3_midside_stereo` — 8-wide AVX2.
- `L3_imdct36` — 8-band structure-of-arrays transform (transpose, vectorized
  9-point DCT butterflies, twiddle/window stage, transpose back).

See `NOTES.md` for details.

## Requirements

- x86-64 CPU with AVX2 (Haswell 2013 or newer). Without AVX2 the code compiles
  to the original SSE/generic paths and behaves exactly like upstream.
- A C89-capable compiler (gcc or clang). Float output
  (`-DMINIMP3_FLOAT_OUTPUT`) and `-DMINIMP3_NO_SIMD` are supported; the
  float-output build is also verified bit-exact.

## Build

Exact (bit-exact, recommended):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffp-contract=off ...
```

Fast (allows FMA/reassociation; still passes conformance):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffast-math ...
```

`-ffp-contract=off` is important: without it gcc fuses multiply-adds into FMA,
which changes the output and breaks bit-exactness.

PGO adds a large further win. Build with the helper (trains on the bundled
vectors, then rebuilds with `-fprofile-use`):

```
scripts/build_opt.sh exact     # or: fast
```

## Verify and benchmark

```
make verify     # bit-exact differential (89 vectors) + upstream conformance
make bench      # PGO build + throughput over the 14-vector suite
```

Or use the scripts directly:

```
harness/diff.sh [flags]                 # candidate vs pristine upstream oracle
harness/conformance.sh src [flags]      # upstream test suite (PSNR/max_diff)
harness/bench_pgo.sh <name> [flags]     # writes results/<name>.csv
```

`upstream/` is a git submodule used as the pristine oracle:

```
git clone --recursive <this repo>
# or, after a normal clone:
git submodule update --init
```

## Repository layout

```
src/        optimized headers (the fork)
bench/      throughput + per-kernel micro-benchmarks
tools/      decode_dump (differential helper)
harness/    differential, conformance, benchmark, compiler-matrix scripts
scripts/    PGO build helper
results/    benchmark CSVs (summary.csv)
NOTES.md    method, full results, rejected experiments
upstream/   pristine lieff/minimp3 submodule (oracle)
```

## Attribution

Based on [minimp3](https://github.com/lieff/minimp3) by lieff and contributors,
dedicated to the public domain under CC0-1.0. This fork is not endorsed by the
upstream author.
