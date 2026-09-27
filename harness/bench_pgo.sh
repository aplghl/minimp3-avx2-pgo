#!/bin/bash
# Build the bench from src/ with PGO + given flags and measure the primary
# vector set. Writes results/<name>.csv and prints the mean ns/sample.
#
# usage: harness/bench_pgo.sh <name> [flags...]
#   TRAIN_SET=all|heldout  (default all)  PGO training corpus
#   BUDGET, REPEATS, PIN, CC               tuning knobs
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:?name required}
shift
FLAGS=${*:-"-O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off"}
CC=${CC:-gcc}
BUDGET=${BUDGET:-0.2}
REPEATS=${REPEATS:-5}
PIN=${PIN:-2}
TRAIN_SET=${TRAIN_SET:-all}

BUILD="$ROOT/build"
RES="$ROOT/results"
PROF="$ROOT/pgo/$NAME"
BIN="$BUILD/bench_$NAME"
mkdir -p "$BUILD" "$RES" "$PROF"

VECTORS=(
    vectors/l3-compl.bit vectors/l3-he_32khz.bit vectors/l3-he_44khz.bit
    vectors/l3-he_48khz.bit vectors/l3-hecommon.bit vectors/l3-he_free.bit
    vectors/l3-he_mode.bit vectors/l3-si.bit vectors/l3-si_block.bit
    vectors/l3-si_huff.bit vectors/l3-sin1k0db.bit
    vectors/performance/MEANDR_PHASE0.mp3 vectors/performance/MIPSTest.mp3
    vectors/performance/noise_meandr.mp3
)

# Build training corpus.
mapfile -t ALL < <(ls "$ROOT"/upstream/vectors/*.bit "$ROOT"/upstream/vectors/performance/*.mp3 "$ROOT"/upstream/vectors/fuzz/*.mp3 2>/dev/null)
if [ "$TRAIN_SET" = "heldout" ]; then
    TRAIN=()
    for f in "${ALL[@]}"; do
        base=$(basename "$f")
        keep=1
        for m in "${VECTORS[@]}"; do
            [ "$base" = "$(basename "$m")" ] && { keep=0; break; }
        done
        [ "$keep" = 1 ] && TRAIN+=("$f")
    done
else
    TRAIN=("${ALL[@]}")
fi

echo "== $NAME : $FLAGS (train=$TRAIN_SET, n=${#TRAIN[@]}) =="
$CC $FLAGS -fprofile-generate="$PROF" -I "$ROOT/src" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1
for f in "${TRAIN[@]}"; do
    taskset -c "$PIN" "$BIN" "$f" 0.02 1 >/dev/null 2>&1
done
$CC $FLAGS -fprofile-use="$PROF" -fprofile-correction -I "$ROOT/src" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1

CSV="$RES/$NAME.csv"
echo "file,ns_per_sample" > "$CSV"
for rel in "${VECTORS[@]}"; do
    f="$ROOT/upstream/$rel"
    [ -e "$f" ] || continue
    line=$(taskset -c "$PIN" "$BIN" "$f" "$BUDGET" "$REPEATS")
    echo "$rel,$(echo "$line" | cut -d, -f5)" >> "$CSV"
done
python3 - "$NAME" "$CSV" <<'PY'
import sys
name, csv = sys.argv[1], sys.argv[2]
vals = [float(l.split(',')[1]) for l in open(csv).read().splitlines()[1:]]
print(f"{name}: n={len(vals)} mean={sum(vals)/len(vals):.3f} ns/sample")
PY
