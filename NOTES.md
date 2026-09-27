# minimp3 optimization notes

Target: Intel i7-14700F (Raptor Lake, AVX2 + FMA + BMI2, no AVX-512), WSL2,
gcc 13.3 only (no clang/perf/llvm-mca, no sudo).

Strategy was compiler-first: establish a bit-exact differential + conformance
harness, exhaust the compiler/PGO headroom, profile, then spend effort only on
proven hot paths. All accepted source changes take effect only on AVX2: the
DSP kernels are guarded by `#if defined(__AVX2__)`, and the pre-existing SSE
bodies are retained verbatim in the `#else` branches, so generic / SSE / NEON
behavior is unchanged.

## Results (14-vector suite, PGO builds, geomean speedup vs upstream `-O2`)

| variant                                   | mean ns/sample | speedup (geomean) |
| ----------------------------------------- | -------------- | ----------------- |
| upstream `-O2` (baseline)                 | 5.830          | —                 |
| earlier exact build before this session (`unroll`) | 3.997 | +47.7% |
| + packed stereo output stores (`c_store`) | 3.843          | +54.1%            |
| + AVX2 SoA IMDCT36 (`exact`)              | 3.492          | **+71.0%**        |
| fast track `-ffast-math` (`fast`)         | 3.430          | **+74.5%**        |

Bit-exact track (`exact`) is byte-identical to upstream on all 89 vectors,
with and without PGO, and passes the full conformance suite. The fast track
also passes conformance (PSNR/max_diff); the FMA advantage has shrunk to ~2%
now that the FP-heavy loops are explicit 256-bit SIMD.

Naming: the final bit-exact build is the one shipped as `results/exact.csv`
(`summary.csv` row `exact`); the final fast build is row `fast`. The
intermediate rows (`unroll`, `c_store`) are earlier stages kept for provenance.
`results/README.md` maps every CSV to its generator and status.

Kernel-level (micro-benchmarks vs upstream `-O2`, same machine; reproduce with
`make kernels`, data in `results/kernels.csv`): `L3_imdct36` +75.6%,
`L3_midside_stereo` +49.5%, `mp3d_DCT_II` +46.6%, `mp3d_synth` +40.2%,
`L3_antialias` +34.7%. (An earlier session recorded larger deltas; the values
above are the ones reproducible from the committed script and are what the docs
quote.)

## Source changes in `src/minimp3.h` (effective only on AVX2)

1. `mp3d_DCT_II`: AVX2 8-wide transform for full 8-band groups, SSE tail.
2. `mp3d_synth`: AVX2 processes two phases (i and i-1) per iteration. The
   4-float `zlin` groups of adjacent phases are contiguous, so one 256-bit load
   feeds both; low 128 lanes = phase i-1, high = phase i. Per-lane operation
   order is identical to the SSE path.
3. `mp3d_synth` output: stereo writes packed L/R 16-bit pairs via
   `_mm_storeu_si32` (mono writes only the 4 meaningful lanes), halving the
   extract/store work.
4. `L3_imdct36` (`L3_imdct36x8`): an 8-band SoA transform. The band-major input
   is transposed with `minimp3_transpose8_ps`, the preprocessing, both 9-point
   `L3_dct3_9` butterflies and the twiddle/window post-stage run 8 bands wide,
   then the result and the overlap are transposed back. Operation order per
   lane matches the scalar path exactly, so it stays bit-exact.
5. `L3_midside_stereo`: AVX2 8-wide.
6. `L3_antialias`: AVX2 8-wide.

The bitstream/huffman/scalefactor paths are untouched.

## What did NOT help (measured and rejected)

- Broadening PGO training from 13 to all 89 vectors: -0.4% (noise).
- `-fno-stack-protector -fno-asynchronous-unwind-tables -fomit-frame-pointer
  -fno-plt -fno-semantic-interposition`: -0.5%.
- `-falign-functions=32 -falign-loops=32`: +0.02%.
- `-fprofile-values -fvpt`: -0.7%.
- `-ftracer`: -0.3%.
- `__attribute__((noinline))` / `((hot))` on `L3_huffman` to break up the
  19.7 KB `mp3dec_decode_frame`: -0.1% / -0.03%.
- Precomputing the per-lane synthesis window vectors into a static table
  (trading broadcast uops for L1 loads): synth regressed ~4%, reverted.

## Build recipes

Exact (bit-exact vs upstream, recommended default):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffp-contract=off ...
```

Important: `-march=native` alone changes results because gcc contracts
multiply-adds into FMA. `-ffp-contract=off` keeps the exact build bit-identical
to the canonical upstream build.

Fast (allows FMA/reassociation, still passes PSNR conformance):

```
gcc -O3 -std=c89 -march=native -mtune=native -funroll-loops -ffast-math ...
```

PGO adds ~10 points on its own and stacks with both. Train on a representative
mix and rebuild with `-fprofile-use`:

```
scripts/build_opt.sh exact      # or: fast
```

## Harness

- `harness/diff.sh [flags]` — builds `tools/decode_dump.c` against the pristine
  `upstream/` header (canonical `-O2 -std=c89`, the oracle) and `src/`, decodes
  all 89 vectors, and requires byte-identical PCM. Set `PGO_DIR=<dir>` to test
  the PGO'd candidate, and `ORACLE_FLAGS=...` to build a matching oracle (used
  by `make verify-portable` for the `NO_SIMD`/`FLOAT_OUTPUT` checks).
- `harness/conformance.sh <hdr_dir> [flags]` — builds upstream `minimp3_test.c`
  against a header dir and runs the full `scripts/test.sh` (PSNR/max_diff and
  mode checks).
- `harness/bench_pgo.sh <name> [flags]` — builds the bench from `src/` with PGO
  and writes `results/<name>.csv`. `TRAIN_SET=heldout` trains without the
  measured vectors for an out-of-sample estimate.
- `harness/matrix.sh` — plain compiler matrix.
- `harness/kernbench.sh` — per-kernel upstream-vs-AVX2 micro-benchmarks, writes
  `results/kernels.csv`.
- `bench/bench.c` — full-buffer decode throughput (ns/sample, TSC cycles/sample,
  min-of-K, `taskset` pinned).
- `bench/kernbench.c` — per-kernel micro-benchmarks (`mp3d_DCT_II`,
  `mp3d_synth`, `L3_imdct36`, `L3_antialias`, `L3_midside_stereo`).

Portability: SSE-only (`-march=x86-64-v2`), AVX2 (`-march=x86-64-v3`,
`-ffp-contract=off`), `-DMINIMP3_NO_SIMD` and `-DMINIMP3_FLOAT_OUTPUT` all
compile and decode bit-identically to a matching upstream oracle (the NO_SIMD
path is untouched; its small divergence from SIMD is pre-existing in upstream).
The float-output build was verified bit-exact against upstream. AVX2 selection
is compile-time only, so a `-march` build that enables AVX2 needs an AVX2 CPU
(there is no runtime AVX2 dispatch).

Sanitizers: `make sanitize` builds the AVX2 candidate with AddressSanitizer +
UBSan and runs all 89 vectors, truncated prefixes of each, and 200 deterministic
pseudo-random buffers (556 inputs). Clean — no memory or undefined-behavior
reports, which also covers the `iscf[40]` bounds concern below.

## Reproducing these claims

```
make verify            # 89/89 bit-exact (plain + PGO) + exact-build conformance
make verify-portable   # SSE-only, AVX2, no-SIMD, float-output, -Werror C89
make conformance-fast  # -ffast-math build conformance (PSNR/max_diff)
make sanitize          # ASan + UBSan over vectors, truncations, random inputs
make kernels           # per-kernel micro-benchmarks
make bench             # end-to-end throughput -> results/exact.csv
```

Timings are machine-specific; the correctness results are not. Three fresh PGO
rebuilds of the exact build spanned 3.46–3.51 ns/sample (1.3% overall,
per-vector up to 4%; `results/variance.csv`), so treat the speedups as
approximate. Last run on the committed source: plain and PGO `harness/diff.sh`
both report `PASS: 89 vectors bit-exact`; the exact and `-ffast-math` builds
both pass conformance; `make verify-portable` passes; and `make sanitize` is
clean over 556 inputs. The one reproducible exception is by design:
`-march=x86-64-v3` *without* `-ffp-contract=off` diverges on
`noise_meandr.mp3` (FMA contraction), which is why the exact build always sets
`-ffp-contract=off`.

## Known warning under PGO

Building the candidate with `-fprofile-use` can emit
`-Wstringop-overflow` in `L3_decode_scalefactors` (the `iscf[40]` writes at
`src/minimp3.h:695-697`). The code is **unchanged from upstream**; the warning
appears only because the added AVX2 code perturbs gcc's value-range analysis.
It is a **false positive**, and this is provable from the values gcc cannot
see: `n_long_sfb`/`n_short_sfb` are only ever set to long `(22,0)`, short
`(0,39)` or mixed `(8,30)`/`(6,30)` (`src/minimp3.h:547-573`). The largest write
index is therefore `n_long_sfb + i + 2` with `i <= n_short_sfb - 3`, i.e.
`0 + 36 + 2 = 38` for short blocks and `8 + 27 + 2 = 37` for mixed — both below
40. Consistent with this, ASan+UBSan over the 89 vectors, truncations and random
inputs is clean (`make sanitize`), and all 89 decode bit-identically.
`make verify` passes.

## Fork layout / commit structure

Commits on top of upstream `ea99364`:

1. scaffold (harness, benchmarks, PGO recipe, docs)
2. `mp3d_DCT_II` AVX2
3. `mp3d_synth` AVX2 + packed stereo stores
4. `L3_antialias` / `L3_midside_stereo` AVX2
5. `L3_imdct36` SoA

Each was verified bit-exact (`harness/diff.sh`) before committing.
`OUTREACH.md` holds the (unposted) upstream issue/PR drafts.

## Remaining headroom (not taken)

- `L3_huffman` is now the top cost on high-bitrate streams (~60% on some
  vectors). It is a serial dependent-load bitstream loop; no safe source-level
  win was found (hints/layout are neutral under PGO, and widening the bit cache
  would risk the OOB fuzz vectors).
- `mp3d_synth` is still 49-64% and remains the dominant cost. The scalar `zlin`
  writes and `mp3d_synth_pair` are the residual scalar parts.
- Short-block `L3_imdct_short`/`L3_imdct12` (~3% on transient-heavy vectors)
  could use the same SoA technique but were not converted.
