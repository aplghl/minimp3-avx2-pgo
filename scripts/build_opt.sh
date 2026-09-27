#!/bin/bash
# Build the optimized minimp3 reference test binary with PGO.
#
# usage: scripts/build_opt.sh [exact|fast] [outdir]
#   exact (default): bit-exact vs upstream; -ffp-contract=off
#   fast           : allows FMA/reassociation (-ffast-math), not bit-exact
#
# The build is single-translation-unit, so this mainly demonstrates the PGO
# workflow. For your own app, replace minimp3_test.c with your TU and train
# with a representative workload.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-exact}
OUT=${2:-"$ROOT/build/opt_$MODE"}
CC=${CC:-gcc}

case "$MODE" in
    exact) FPF="-ffp-contract=off" ;;
    fast)  FPF="-ffast-math" ;;
    *) echo "unknown mode: $MODE (expected exact|fast)"; exit 2 ;;
esac

FLAGS="-O3 -std=c89 -march=native -mtune=native -funroll-loops $FPF"
PROF="$ROOT/pgo/build_$MODE"

rm -rf "$OUT" "$PROF"
mkdir -p "$OUT/scripts" "$PROF"
cp "$ROOT/upstream/minimp3_test.c" "$OUT/"
cp "$ROOT/src/minimp3.h" "$ROOT/src/minimp3_ex.h" "$OUT/"
cp "$ROOT/upstream/scripts/test.sh" "$OUT/scripts/"
ln -s "$ROOT/upstream/vectors" "$OUT/vectors"

TRAIN=(
    l3-compl l3-he_32khz l3-he_44khz l3-he_48khz l3-hecommon l3-he_free
    l3-he_mode l3-si l3-si_block l3-si_huff l3-sin1k0db
)

echo "== pass 1: -fprofile-generate ($MODE) =="
$CC $FLAGS -fprofile-generate="$PROF" -o "$OUT/minimp3" "$OUT/minimp3_test.c" -lm
for v in "${TRAIN[@]}"; do
    "$OUT/minimp3" "$OUT/vectors/$v.bit" "$OUT/vectors/$v.pcm" >/dev/null 2>&1 || true
done

echo "== pass 2: -fprofile-use ($MODE) =="
$CC $FLAGS -fprofile-use="$PROF" -fprofile-correction -o "$OUT/minimp3" "$OUT/minimp3_test.c" -lm

echo "== conformance =="
( cd "$OUT" && bash scripts/test.sh ) > "$OUT/conformance.log" 2>&1
echo "PASS ($MODE): $OUT/minimp3, log: $OUT/conformance.log"
