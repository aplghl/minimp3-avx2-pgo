#!/bin/bash
# Sanitizer gate: build the candidate with AddressSanitizer + UBSan and run
# every bundled vector, truncated prefixes, and deterministic pseudo-random
# buffers, looking for memory or undefined-behavior errors.
#
# usage: harness/sanitize.sh [extra gcc flags...]
#   FUZZ_N=<n>   number of pseudo-random buffers (default 200)
#   TRUNC=<n>    truncation points per vector (default 3)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"
CC=${CC:-gcc}
FLAGS=${*:-"-O1 -g -std=gnu11 -march=x86-64-v3 -ffp-contract=off"}
SAN="-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
FUZZ_N=${FUZZ_N:-200}
TRUNC=${TRUNC:-3}

echo "== sanitizers: $FLAGS $SAN =="
$CC $FLAGS $SAN -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_asan" || exit 1

fail=0
n=0
run()
{
    out=$("$BUILD/dump_asan" "$1" 2>&1 >/dev/null); rc=$?
    n=$((n + 1))
    if [ $rc -ne 0 ] || echo "$out" | grep -qE "Sanitizer|runtime error"; then
        echo "SANITIZER: $1 (rc=$rc)"
        echo "$out" | head -10
        fail=1
    fi
}

for f in "$ROOT"/upstream/vectors/*.bit "$ROOT"/upstream/vectors/performance/*.mp3 "$ROOT"/upstream/vectors/fuzz/*.mp3; do
    [ -e "$f" ] || continue
    run "$f"
    size=$(stat -c%s "$f")
    for t in $(seq 1 "$TRUNC"); do
        len=$(( size * t / (TRUNC + 1) ))
        [ "$len" -gt 0 ] || continue
        head -c "$len" "$f" > "$BUILD/_trunc.mp3"
        run "$BUILD/_trunc.mp3"
    done
done

for i in $(seq 1 "$FUZZ_N"); do
    len=$(( (i * 2654435761 % 4096) + 16 ))
    python3 -c "import random,sys; random.seed(int(sys.argv[1])); open(sys.argv[2],'wb').write(bytes(random.getrandbits(8) for _ in range(int(sys.argv[3]))))" "$i" "$BUILD/_rand.mp3" "$len"
    run "$BUILD/_rand.mp3"
done

rm -f "$BUILD/_trunc.mp3" "$BUILD/_rand.mp3"
if [ "$fail" -eq 0 ]; then
    echo "PASS: sanitizers clean ($n inputs)"
else
    echo "FAIL: sanitizer error detected"
fi
exit $fail
