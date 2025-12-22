#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GETH_BIN_DEFAULT="/home/mikers/dev/snissn/op-geth/build/bin/geth"
GETH_BIN="${GETH_BIN:-$GETH_BIN_DEFAULT}"

CALLS_PER_BLOCK="${CALLS_PER_BLOCK:-5}"
NUM_BLOCKS="${NUM_BLOCKS:-5}"
GAS_PER_TX="${GAS_PER_TX:-2000000}"
GAS_LIMIT="${GAS_LIMIT:-30000000}"

BENCH_ROOT_DIR_BASE="${BENCH_ROOT_DIR_BASE:-$ROOT_DIR/data-dir}"
BENCH_OUTPUT_DIR_BASE="${BENCH_OUTPUT_DIR_BASE:-$ROOT_DIR/output}"

for engine in leveldb treedb; do
  export OP_GETH_DB_TRACE_PATH=/tmp/${engine}-trace-${PAYLOAD_ID}-$(date +%s).jsonl.gz
  echo "=== Running KV stress with ${engine} ==="
  rm -rf "${BENCH_ROOT_DIR_BASE}-${engine}" "${BENCH_OUTPUT_DIR_BASE}-${engine}"
  mkdir -p "${BENCH_ROOT_DIR_BASE}-${engine}" "${BENCH_OUTPUT_DIR_BASE}-${engine}"
  DB_ENGINE="$engine" \
  GETH_BIN="$GETH_BIN" \
  CALLS_PER_BLOCK="$CALLS_PER_BLOCK" \
  NUM_BLOCKS="$NUM_BLOCKS" \
  GAS_PER_TX="$GAS_PER_TX" \
  GAS_LIMIT="$GAS_LIMIT" \
  BENCH_ROOT_DIR="${BENCH_ROOT_DIR_BASE}-${engine}" \
  BENCH_OUTPUT_DIR="${BENCH_OUTPUT_DIR_BASE}-${engine}" \
  "$ROOT_DIR/run-bench-geth-kv.sh"
done
