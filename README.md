# minimp3-avx2

An AVX2-optimized fork of [minimp3](https://github.com/lieff/minimp3) (single
header MP3 decoder), plus a reproducible PGO build recipe and a differential
correctness/benchmark harness.

- **Upstream base:** `lieff/minimp3` at commit
  [`ea99364`](https://github.com/lieff/minimp3/tree/ea99364f61c14656440e8d77e9c233ccf3124633)
  (tracked as the `upstream/` submodule, used as the pristine oracle).
- **License:** CC0-1.0, same as upstream. See `LICENSE`.

> Developed with AI assistance. Every change is verified by the included
> bit-exact differential harness and the upstream conformance suite; see
> `NOTES.md` for the method, full results, and rejected experiments.

## Results

Decoding throughput over a 14-vector suite, geometric mean against stock
upstream `-O2` (Intel i7-14700F; gcc 13.3; see `NOTES.md` for the full table):

| build | mean ns/sample | throughput vs upstream |
| ----- | -------------- | ---------------------- |
| upstream `-O2` | 5.830 | baseline |
| this fork, **exact** (AVX2 + PGO) | 3.492 | **+71%** |
| this fork, **fast** (`-ffast-math`, FMA) | 3.430 | **+74.5%** |

The exact build is **bit-identical** to upstream on all 89 test vectors, with
and without PGO, and passes the upstream conformance suite. The fast build also
passes conformance (PSNR/max_diff); FMA/reassociation means it is not bit-exact.
Timings are single-machine and approximate: three fresh exact rebuilds spanned
3.46–3.51 ns/sample (1.3%), so read the percentages as ~±2%
(`results/variance.csv`).

Kernel-level speedups (vs upstream `-O2`, same machine): `L3_imdct36` +76%,
`L3_midside_stereo` +50%, `mp3d_DCT_II` +47%, `mp3d_synth` +40%,
`L3_antialias` +35%. Reproduce with `make kernels`; data in
`results/kernels.csv`.

## Quickstart

```
git clone --recursive <this repo>     # or: git submodule update --init
make verify          # bit-exact (89 vectors, plain + PGO) + conformance
make verify-portable # SSE-only / AVX2 / no-SIMD / float-output / -Werror
make bench           # PGO build + throughput -> results/exact.csv
```

## What changed, and what did not

Only **`src/minimp3.h`** is modified. `src/minimp3_ex.h` is **byte-identical**
to upstream. The diff is small and local: roughly +439/−66 lines, most of the
deletions being pre-existing SSE bodies re-nested (not rewritten).

### Touched (all take effect only on AVX2)

Each kernel follows the file's existing compile-time gating pattern
(`#if defined(__AVX2__)`, alongside the SSE/NEON paths) and is dispatched
through the existing `have_simd()` check. No runtime CPU dispatch is added.

- `mp3d_DCT_II` — 8-wide AVX2 transform for full 8-band groups; SSE tail for
  the remainder.
- `mp3d_synth` — two filter phases per 256-bit iteration (the 4-float `zlin`
  groups of adjacent phases are contiguous, so one 256-bit load feeds both),
  plus packed stereo output stores (`_mm_storeu_si32`) via a new `SYNTH_STORE`
  macro. Per-lane arithmetic order matches the SSE path exactly.
- `L3_antialias`, `L3_midside_stereo` — 8-wide AVX2.
- `L3_imdct36` — 8-band structure-of-arrays transform: transpose in, vectorized
  9-point `L3_dct3_9` butterflies and twiddle/window stage, transpose out.
  Scalar tail for leftover bands.

### Not touched

- **`src/minimp3_ex.h`** — byte-identical to upstream.
- **Bitstream / Huffman / scalefactor / intensity-stereo / reorder /**
  **accumulation paths** — untouched.
- **Public API, structs, build system, license** — unchanged.
- **Generic, SSE, NEON and `-DMINIMP3_NO_SIMD` paths** — behavior unchanged;
  on a non-AVX2 target the output is byte-identical to upstream (verified with
  `-march=x86-64-v2`, i.e. SSE-only).

## Exact vs fast, and PGO

`-ffp-contract=off` is what keeps the build bit-exact. Without it, gcc on an
FMA-capable target contracts multiply-adds into FMA, changing the output — this
is reproducible: `-march=x86-64-v3` without `-ffp-contract=off` diverges on
`noise_meandr.mp3`.

Exact (bit-exact, recommended default):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffp-contract=off ...
```

Fast (allows FMA/reassociation; passes conformance, not bit-exact):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffast-math ...
```

PGO adds ~10 points on its own and stacks with both. Train on a representative
mix, then rebuild with `-fprofile-use`:

```
scripts/build_opt.sh exact     # or: fast
```

Under PGO, gcc may emit a `-Wstringop-overflow` warning in
`L3_decode_scalefactors`. That code is unchanged from upstream and the warning
is a provable false positive (the index is bounded below 40 by the only values
`n_long_sfb`/`n_short_sfb` can take); `make sanitize` is clean. See `NOTES.md`.

## Verify and benchmark

```
make verify            # bit-exact (89 vectors, plain + PGO) + exact conformance
make verify-portable   # SSE-only / AVX2 / no-SIMD / float-output / -Werror
make conformance-fast  # -ffast-math build conformance (PSNR/max_diff)
make sanitize          # ASan+UBSan over vectors, truncations, random inputs
make bench             # PGO build + throughput over the 14-vector suite
make kernels           # per-kernel micro-benchmarks -> results/kernels.csv
```

Or use the scripts directly:

```
harness/diff.sh [flags]                 # candidate vs pristine upstream oracle
harness/conformance.sh src [flags]      # upstream test suite (PSNR/max_diff)
harness/bench_pgo.sh <name> [flags]     # writes results/<name>.csv
harness/kernbench.sh                    # per-kernel micro-benchmarks
harness/sanitize.sh                     # ASan+UBSan gate
```

The oracle is always built with canonical upstream flags (`-O2 -std=c89`) so
that any numeric change from candidate source changes *or* candidate flags is
caught. Set `ORACLE_FLAGS` to build a matching oracle (e.g. for `NO_SIMD` or
`FLOAT_OUTPUT` checks), and `PGO_DIR=<dir>` to test the PGO'd candidate.

`upstream/` is a git submodule used as the pristine oracle:

```
git clone --recursive <this repo>
# or, after a normal clone:
git submodule update --init
```

## Requirements and portability

- x86-64 CPU with AVX2 (Haswell 2013 or newer). The AVX2 kernels are selected
  at **compile time** via `__AVX2__`; there is **no runtime AVX2 dispatch**.
  `have_simd()` is upstream's existing guard and checks SSE2, not AVX2. A build
  without AVX2 enabled uses the unchanged SSE/generic paths and is byte-identical
  to upstream (e.g. `-march=x86-64-v2`). A build **with** AVX2 enabled requires
  an AVX2 CPU or it will fault, the usual `-march` contract — target a lower
  baseline if you need to run on older CPUs.
- A C89-capable compiler. Verified with gcc 13.3; clang uses the same
  intrinsics and is expected to work but was not tested here. The header is
  clean under `-std=c89 -Wall -Wextra -Werror`.

Verified configurations:

| configuration | flags | result |
| ------------- | ----- | ------ |
| generic / SSE-only | `-march=x86-64-v2` | bit-exact (89/89) |
| AVX2 | `-march=x86-64-v3 -ffp-contract=off` | bit-exact (89/89) |
| no SIMD | `-DMINIMP3_NO_SIMD` | bit-exact (89/89 vs matched oracle) |
| float output | `-DMINIMP3_FLOAT_OUTPUT` | bit-exact (89/89) |
| C89 warnings | `-std=c89 -Wall -Wextra -Werror` | clean |

`make verify-portable` runs all of the above.

## Repository layout

```
src/        optimized headers (the fork)
bench/      throughput + per-kernel micro-benchmarks
tools/      decode_dump (differential helper)
harness/    differential, conformance, benchmark, kernel, compiler-matrix scripts
scripts/    PGO build helper
results/    benchmark CSVs + results/README.md (what each file is)
.github/    CI: portable correctness (make verify-portable)
NOTES.md    method, full results, rejected experiments
OUTREACH.md upstream issue/PR drafts (local only, not posted)
upstream/   pristine lieff/minimp3 submodule (oracle)
```

## Attribution

Based on [minimp3](https://github.com/lieff/minimp3) by lieff and contributors,
dedicated to the public domain under CC0-1.0. This fork is not endorsed by the
upstream author.
