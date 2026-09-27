#!/bin/bash
# Build upstream's conformance test against a chosen header dir and run it
# over the full vector set (compares against reference .pcm, reports PSNR/max_diff).
#
# usage: harness/conformance.sh [header_dir] [extra gcc flags...]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HDR=${1:-"$ROOT/src"}
shift 2>/dev/null || true
EXTRA="$*"
CC=${CC:-gcc}

OUT="$ROOT/build/conf_$(basename "$HDR")"
rm -rf "$OUT"
mkdir -p "$OUT/scripts"
cp "$ROOT/upstream/minimp3_test.c" "$OUT/"
cp "$HDR/minimp3.h" "$HDR/minimp3_ex.h" "$OUT/"
cp "$ROOT/upstream/scripts/test.sh" "$OUT/scripts/"
[ -e "$OUT/vectors" ] || ln -s "$ROOT/upstream/vectors" "$OUT/vectors"

CFLAGS="-O2 -std=c89 -w -fno-asynchronous-unwind-tables -fno-stack-protector -U_FORTIFY_SOURCE -ffunction-sections -fdata-sections -Wl,--gc-sections $EXTRA"
$CC $CFLAGS -o "$OUT/minimp3" "$OUT/minimp3_test.c" -lm || exit 1

( cd "$OUT" && bash scripts/test.sh ) > "$OUT/conformance.log" 2>&1
rc=$?
if [ $rc -eq 0 ]; then
    echo "PASS conformance ($HDR) -> $OUT/conformance.log"
else
    echo "FAIL conformance ($HDR) -> $OUT/conformance.log"
fi
exit $rc
