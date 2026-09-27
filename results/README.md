# results

Raw benchmark CSVs from the development of this fork. Timings are
machine-specific (Intel i7-14700F, WSL2, gcc 13.3) and load-sensitive; treat the
*ranking* as the signal, not the absolute ns/sample. Correctness is verified
separately by `make verify` and is not machine-specific.

All files were produced by the harness in `../harness/` (see each row). Nothing
here is required to build or verify the fork; the directory is kept for
provenance so the claims in `../NOTES.md` can be traced. Timing runs vary:
three fresh PGO rebuilds of the exact build (same flags) gave 14-vector means of
3.478 / 3.463 / 3.508 ns/sample — an overall spread of **1.3%** (per-vector up
to ~4%; see `variance.csv`). The canonical numbers in `summary.csv` come from
`exact.csv` and `fast.csv`, which sit inside that range.

## Final builds

| file | generator | what it is |
| ---- | --------- | ---------- |
| `summary.csv` | hand-assembled | headline table: mean ns/sample and geomean speedup vs upstream `-O2` for each stage |
| `exact.csv` | `harness/bench_pgo.sh exact ...` | **canonical** final bit-exact build (AVX2 + PGO) — the 3.492 headline |
| `fast.csv` | `harness/bench_pgo.sh fast ...` | **canonical** final fast build (`-ffast-math` + PGO) — the 3.430 headline |
| `matrix.csv` | `harness/matrix.sh` | plain compiler matrix (`O2`, `O3`, `O3_native`, `O3_lto_native`, `O3_fma`) over the 14 vectors |
| `kernels.csv` | `harness/kernbench.sh` | per-kernel micro-benchmarks, upstream `-O2` vs the AVX2 fork |

## Superseded runs

| file | what it is |
| ---- | ---------- |
| `exact-repro.csv` | later reproduction of the exact build (~3.51; shows the ~1% variance) |
| `fast-early.csv` | earlier fast-track run, superseded by `fast.csv` (~3.88) |

## Variance study

| file | what it is |
| ---- | ---------- |
| `exact-run1.csv`, `exact-run2.csv`, `exact-run3.csv` | three independent PGO rebuilds of the exact build under identical flags |
| `variance.csv` | per-vector min/mean/max and spread across those three runs, plus the overall run-mean spread (1.3%) |

## Accepted intermediate stage

| file | what it is |
| ---- | ---------- |
| `unroll.csv` | bit-exact AVX2 build before this session (pre-IMDCT36/packed-store), kept as the progression step in `summary.csv`/`NOTES.md` |
| `c_store.csv` | `unroll` + packed stereo output stores (accepted, superseded) |

## Rejected experiments (measured, did not help)

Each is a full per-vector run of the same 14-vector suite under a candidate
change; see `../NOTES.md` "What did NOT help" for the deltas.

| file | experiment |
| ---- | ---------- |
| `a1_all.csv` | PGO trained on all 89 vectors instead of 13 |
| `b_hot.csv` | `__attribute__((hot))` on `L3_huffman` |
| `b_noinline.csv` | `__attribute__((noinline))` on `L3_huffman` |
| `f_align.csv` | `-falign-functions=32 -falign-loops=32` |
| `f_nox.csv` | `-fno-stack-protector -fno-asynchronous-unwind-tables -fomit-frame-pointer -fno-plt -fno-semantic-interposition` |
| `f_pvpt.csv` | `-fprofile-values -fvpt` |
| `f_tracer.csv` | `-ftracer` |

## Earlier phase snapshots

| file | what it is |
| ---- | ---------- |
| `phase1_cmp.csv` | Phase 1 compiler comparison (`O2`, `O3`, `O3_native`, `O3_lto_native`, `pgo`, `O3_fma`), per-vector |
| `phase3_synth.csv` | Phase 3 synthesis experiment: scalar-PGO baseline vs candidate-PGO, per-vector |
| `cand2.csv` | second candidate iteration snapshot |
