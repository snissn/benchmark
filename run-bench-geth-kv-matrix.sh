#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GETH_BIN_DEFAULT="/Users/michaelseiler/dev/snissn/op-geth/build/bin/geth"
GETH_BIN="${GETH_BIN:-$GETH_BIN_DEFAULT}"

REPS="${REPS:-3}"
RANDOMIZE="${RANDOMIZE:-1}"
CLEAN_ROOT="${CLEAN_ROOT:-1}"

TS="${TS:-$(date +%Y%m%d-%H%M%S)}"
OUT_BASE="${OUT_BASE:-$ROOT_DIR/output/matrix-$TS}"
mkdir -p "$OUT_BASE"

if [[ ! -x "$GETH_BIN" ]]; then
  echo "ERROR: geth binary not found or not executable: $GETH_BIN" >&2
  exit 1
fi

configs=()
for scheme in hash path; do
  configs+=("leveldb,$scheme,")
done
for scheme in hash path; do
  for profile in fast safe; do
    configs+=("treedb,$scheme,$profile")
  done
done

if [[ "$RANDOMIZE" == "1" ]]; then
  shuffled="$(printf '%s\n' "${configs[@]}" | python - <<'PY'
import sys
import random

items = [line.strip() for line in sys.stdin if line.strip()]
random.shuffle(items)
print("\n".join(items))
PY
  )"
  configs=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    configs+=("$line")
  done <<<"$shuffled"
fi

for rep in $(seq 1 "$REPS"); do
  for cfg in "${configs[@]}"; do
    IFS=',' read -r engine scheme profile <<<"$cfg"

    label="${engine}-${scheme}"
    if [[ "$engine" == "treedb" ]]; then
      label="${label}-${profile}"
    fi

    rootdir="/tmp/bb-${TS}-${label}-r${rep}"
    outdir="$OUT_BASE/${label}-r${rep}"

    rm -rf "$rootdir"
    mkdir -p "$rootdir" "$outdir"

    export GETH_BIN
    export BENCH_ROOT_DIR="$rootdir"
    export BENCH_OUTPUT_DIR="$outdir"
    export DB_ENGINE="$engine"
    export NODE_ARGS_EXTRA="--state.scheme=${scheme}"

    if [[ "$engine" == "treedb" ]]; then
      export OP_GETH_TREEDB_PROFILE="$profile"
    else
      unset OP_GETH_TREEDB_PROFILE || true
    fi

    echo "=== ${label} rep ${rep}/${REPS} ==="
    "$ROOT_DIR/run-bench-geth-kv.sh"

    if [[ "$CLEAN_ROOT" == "1" ]]; then
      rm -rf "$rootdir"
    fi
  done
done

echo "Wrote matrix outputs to: $OUT_BASE"
