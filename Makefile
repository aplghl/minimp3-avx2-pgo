# minimp3-avx2 convenience targets.

EXACT_FLAGS ?= -O3 -std=gnu11 -march=native -mtune=native -ffp-contract=off -funroll-loops
FAST_FLAGS  ?= -O3 -std=gnu11 -march=native -mtune=native -ffast-math -funroll-loops

.PHONY: all verify diff conformance bench build-exact build-fast clean

all: verify

## Bit-exact differential test against the pristine upstream oracle.
diff:
	bash harness/diff.sh $(EXACT_FLAGS)

## Upstream conformance suite (PSNR / max_diff / mode checks).
conformance:
	bash harness/conformance.sh "$(CURDIR)/src" $(subst -std=gnu11,-std=c89,$(EXACT_FLAGS))

## Full correctness gate: bit-exact + conformance, plus the PGO'd candidate.
verify: diff conformance
	PGO_DIR="$(CURDIR)/pgo/verify" bash harness/diff.sh $(EXACT_FLAGS)

## PGO build + throughput over the primary 14-vector suite.
bench:
	bash harness/bench_pgo.sh exact $(EXACT_FLAGS)
	@echo "results written to results/exact.csv"

build-exact:
	bash scripts/build_opt.sh exact

build-fast:
	bash scripts/build_opt.sh fast

clean:
	rm -rf build pgo
