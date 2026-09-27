#!/bin/bash
# Phase 1 compiler matrix: build the bench against src/ with each flag set and
# measure the primary performance vectors. Appends CSV to results/matrix.csv
#
# usage: harness/matrix.sh [budget] [repeats]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
RES="$ROOT/results"
mkdir -p "$BUILD" "$RES"
CC=${CC:-gcc}
BUDGET=${1:-0.25}
REPEATS=${2:-5}
PIN=${PIN:-2}

VECTORS=(
    vectors/l3-compl.bit
    vectors/l3-he_32khz.bit
    vectors/l3-he_44khz.bit
    vectors/l3-he_48khz.bit
    vectors/l3-hecommon.bit
    vectors/l3-he_free.bit
    vectors/l3-he_mode.bit
    vectors/l3-si.bit
    vectors/l3-si_block.bit
    vectors/l3-si_huff.bit
    vectors/l3-sin1k0db.bit
    vectors/performance/MEANDR_PHASE0.mp3
    vectors/performance/MIPSTest.mp3
    vectors/performance/noise_meandr.mp3
)

# name|flags
VARIANTS=(
    "O2|-O2 -std=gnu11"
    "O3|-O3 -std=gnu11"
    "O3_native|-O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off"
    "O3_lto_native|-O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off -flto"
    "O3_fma|-O3 -std=gnu11 -march=native -mtune=native -ffast-math -flto"
)

CSV="$RES/matrix.csv"
echo "variant,file,bytes,samples,iters,ns_per_sample,cycles_per_sample,Msamples_per_s" > "$CSV"

for v in "${VARIANTS[@]}"; do
    name=${v%%|*}
    flags=${v#*|}
    bin="$BUILD/bench_$name"
    echo "== building $name : $flags =="
    $CC $flags -I "$ROOT/src" "$ROOT/bench/bench.c" -lm -o "$bin" || { echo "build failed: $name"; continue; }
    for rel in "${VECTORS[@]}"; do
        f="$ROOT/upstream/$rel"
        [ -e "$f" ] || continue
        line=$(taskset -c "$PIN" "$bin" "$f" "$BUDGET" "$REPEATS")
        line=${line//$ROOT\//}
        echo "$name,$line" | tee -a "$CSV"
    done
done
echo "CSV: $CSV"
