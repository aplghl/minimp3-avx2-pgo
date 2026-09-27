#!/bin/bash
# Bit-exact differential test: candidate (src/) vs upstream oracle (upstream/).
# Builds two decode_dump binaries, decodes every vector, compares raw PCM output.
#
# The oracle is ALWAYS built with canonical upstream flags (-O2 -std=c89) so that
# any numeric change caused by candidate source changes OR candidate flags is
# detected. Candidate flags come from CLI args (or CAND_FLAGS env).
#
# PGO: if PGO_DIR is set (non-empty), the candidate is built with
# -fprofile-generate, trained on the training vector list, then rebuilt with
# -fprofile-use. The same output name is used so .gcda names match.
#
# usage: harness/diff.sh [extra candidate flags...]
#   PGO_DIR=/abs/dir harness/diff.sh -O3 -march=native -ffp-contract=off
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"

CC=${CC:-gcc}
CAND_FLAGS=${CAND_FLAGS:-"-O2 -std=gnu11"}
[ $# -gt 0 ] && CAND_FLAGS="$*"
# Override to build a matching oracle (e.g. ORACLE_FLAGS="-O2 -std=c89 -DMINIMP3_NO_SIMD").
ORACLE_FLAGS=${ORACLE_FLAGS:-"-O2 -std=c89"}
PGO_DIR=${PGO_DIR:-}

TRAIN=(
    vectors/l3-compl.bit vectors/l3-he_32khz.bit vectors/l3-he_44khz.bit
    vectors/l3-he_48khz.bit vectors/l3-hecommon.bit vectors/l3-he_free.bit
    vectors/l3-he_mode.bit vectors/l3-si.bit vectors/l3-si_block.bit
    vectors/l3-si_huff.bit vectors/l3-sin1k0db.bit
    vectors/performance/MIPSTest.mp3 vectors/performance/noise_meandr.mp3
)

echo "== differential: oracle='$ORACLE_FLAGS' candidate='$CAND_FLAGS' pgo='${PGO_DIR:-none}' =="
$CC $ORACLE_FLAGS -I "$ROOT/upstream" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_oracle" || exit 1

if [ -n "$PGO_DIR" ]; then
    rm -rf "$PGO_DIR" && mkdir -p "$PGO_DIR"
    $CC $CAND_FLAGS -fprofile-generate="$PGO_DIR" -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
    for rel in "${TRAIN[@]}"; do
        "$BUILD/dump_cand" "$ROOT/upstream/$rel" >/dev/null 2>&1
    done
    $CC $CAND_FLAGS -fprofile-use="$PGO_DIR" -fprofile-correction -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
else
    $CC $CAND_FLAGS -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
fi

fail=0
n=0
for f in "$ROOT"/upstream/vectors/*.bit "$ROOT"/upstream/vectors/performance/*.mp3 "$ROOT"/upstream/vectors/fuzz/*.mp3; do
    [ -e "$f" ] || continue
    "$BUILD/dump_oracle" "$f" > "$BUILD/_o.bin" 2>/dev/null
    "$BUILD/dump_cand"   "$f" > "$BUILD/_c.bin" 2>/dev/null
    if ! cmp -s "$BUILD/_o.bin" "$BUILD/_c.bin"; then
        echo "DIFF: ${f#$ROOT/}"
        fail=1
    fi
    n=$((n + 1))
done
rm -f "$BUILD/_o.bin" "$BUILD/_c.bin"
if [ "$fail" -eq 0 ]; then
    echo "PASS: $n vectors bit-exact"
else
    echo "FAIL: divergence detected"
fi
exit $fail
