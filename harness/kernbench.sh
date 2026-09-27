#!/bin/bash
# Per-kernel micro-benchmarks: pristine upstream oracle vs the AVX2 fork.
# Builds bench/kernbench.c twice and writes results/kernels.csv.
#
# usage: harness/kernbench.sh [budget] [repeats]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
RES="$ROOT/results"
mkdir -p "$BUILD" "$RES"
CC=${CC:-gcc}
BUDGET=${1:-0.2}
REPEATS=${2:-5}
PIN=${PIN:-2}
UP_FLAGS=${UP_FLAGS:-"-O2 -std=gnu11"}
AVX_FLAGS=${AVX_FLAGS:-"-O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off -funroll-loops"}

KERNELS=(dct2 synth antialias midside imdct36)

$CC $UP_FLAGS  -I "$ROOT/upstream" "$ROOT/bench/kernbench.c" -lm -o "$BUILD/kernbench_up"   || exit 1
$CC $AVX_FLAGS -I "$ROOT/src"      "$ROOT/bench/kernbench.c" -lm -o "$BUILD/kernbench_avx2" || exit 1

CSV="$RES/kernels.csv"
echo "kernel,upstream_ns,avx2_ns,speedup_pct" > "$CSV"
for k in "${KERNELS[@]}"; do
    up=$(taskset -c "$PIN" "$BUILD/kernbench_up"   "$k" "$BUDGET" "$REPEATS" | cut -d, -f2)
    av=$(taskset -c "$PIN" "$BUILD/kernbench_avx2" "$k" "$BUDGET" "$REPEATS" | cut -d, -f2)
    sp=$(python3 -c "print(f'{100.0*(${up}-${av})/${up}:.1f}')")
    echo "$k,$up,$av,$sp" | tee -a "$CSV"
done
