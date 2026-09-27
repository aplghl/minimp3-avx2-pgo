# minimp3-avx2 convenience targets.

# Use gcc unless the caller provides CC (make's built-in default is 'cc').
ifeq ($(origin CC),default)
CC := gcc
endif
export CC
EXACT_FLAGS ?= -O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off -funroll-loops
FAST_FLAGS  ?= -O3 -std=gnu11 -march=native -mtune=native -ffast-math -funroll-loops
PORTABLE_FLAGS ?= -O2 -std=gnu11

.PHONY: all verify verify-portable sanitize diff conformance conformance-fast bench kernels build-exact build-fast clean

all: verify

## Bit-exact differential test against the pristine upstream oracle.
diff:
	bash harness/diff.sh $(EXACT_FLAGS)

## Upstream conformance suite (PSNR / max_diff / mode checks).
conformance:
	bash harness/conformance.sh "$(CURDIR)/src" $(subst -std=gnu11,-std=c89,$(EXACT_FLAGS))

## Conformance for the fast (-ffast-math) build.
conformance-fast:
	bash harness/conformance.sh "$(CURDIR)/src" $(subst -std=gnu11,-std=c89,$(FAST_FLAGS))

## Full correctness gate: bit-exact + conformance, plus the PGO'd candidate.
verify: diff conformance
	PGO_DIR="$(CURDIR)/pgo/verify" bash harness/diff.sh $(EXACT_FLAGS)

## Portability gate: SSE-only, AVX2, no-SIMD, float output, C89 -Werror.
verify-portable:
	@mkdir -p build
	bash harness/diff.sh $(PORTABLE_FLAGS) -march=x86-64-v2
	bash harness/diff.sh $(PORTABLE_FLAGS) -march=x86-64-v3 -ffp-contract=off
	ORACLE_FLAGS="-O2 -std=c89 -DMINIMP3_NO_SIMD" bash harness/diff.sh $(PORTABLE_FLAGS) -DMINIMP3_NO_SIMD
	ORACLE_FLAGS="-O2 -std=c89 -DMINIMP3_FLOAT_OUTPUT" bash harness/diff.sh $(PORTABLE_FLAGS) -DMINIMP3_FLOAT_OUTPUT
	$(CC) -O2 -std=c89 -Wall -Wextra -Werror -Isrc -c tools/decode_dump.c -o build/decode_dump_werror.o
	@echo "PASS verify-portable"

## Sanitizer gate: ASan + UBSan over all vectors, truncations and random inputs.
sanitize:
	bash harness/sanitize.sh
	@echo "PASS sanitize"

## PGO build + throughput over the primary 14-vector suite.
bench:
	bash harness/bench_pgo.sh exact $(EXACT_FLAGS)
	@echo "results written to results/exact.csv"

## Per-kernel micro-benchmarks (upstream vs AVX2) -> results/kernels.csv.
kernels:
	bash harness/kernbench.sh
	@echo "results written to results/kernels.csv"

build-exact:
	bash scripts/build_opt.sh exact

build-fast:
	bash scripts/build_opt.sh fast

clean:
	rm -rf build pgo
