#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GETH_BIN_DEFAULT="/home/mikers/dev/snissn/op-geth/build/bin/geth"
GETH_BIN="${GETH_BIN:-$GETH_BIN_DEFAULT}"

scenarios=(
  "sload-readheavy"
  "sstore-writeheavy"
  "sstore-manytx"
)

for scenario in "${scenarios[@]}"; do
  case "$scenario" in
    sload-readheavy)
      BENCH_NAME="SLOAD read-heavy"
      BENCH_DESC="Read-heavy storage workload to stress KV reads."
      PAYLOAD_NAME="SLOAD read-heavy"
      PAYLOAD_ID="sload"
      FUNC_SIGNATURE="reader(uint256,bytes)"
      CALLS_PER_BLOCK=10
      NUM_BLOCKS=5
      GAS_PER_TX=2000000
      GAS_LIMIT=30000000
      ;;
    sstore-writeheavy)
      BENCH_NAME="SSTORE write-heavy"
      BENCH_DESC="Write-heavy storage workload to stress KV writes."
      PAYLOAD_NAME="SSTORE write-heavy"
      PAYLOAD_ID="sstore"
      FUNC_SIGNATURE="writer(uint256,bytes)"
      CALLS_PER_BLOCK=10
      NUM_BLOCKS=5
      GAS_PER_TX=3000000
      GAS_LIMIT=60000000
      ;;
    sstore-manytx)
      BENCH_NAME="SSTORE many-tx"
      BENCH_DESC="Many smaller storage writes to stress tx throughput and KV churn."
      PAYLOAD_NAME="SSTORE many-tx"
      PAYLOAD_ID="sstore"
      FUNC_SIGNATURE="writer(uint256,bytes)"
      CALLS_PER_BLOCK=40
      NUM_BLOCKS=5
      GAS_PER_TX=500000
      GAS_LIMIT=30000000
      ;;
    *)
      echo "Unknown scenario: $scenario" >&2
      exit 1
      ;;
  esac

  BENCH_ROOT_DIR_BASE="$ROOT_DIR/data-dir-${scenario}"
  BENCH_OUTPUT_DIR_BASE="$ROOT_DIR/output-${scenario}"

  echo "=== Scenario: ${scenario} ==="
  BENCH_NAME="$BENCH_NAME" \
  BENCH_DESC="$BENCH_DESC" \
  PAYLOAD_NAME="$PAYLOAD_NAME" \
  PAYLOAD_ID="$PAYLOAD_ID" \
  FUNC_SIGNATURE="$FUNC_SIGNATURE" \
  NODE_ARGS_EXTRA="--ipcdisable" \
  CALLS_PER_BLOCK="$CALLS_PER_BLOCK" \
  NUM_BLOCKS="$NUM_BLOCKS" \
  GAS_PER_TX="$GAS_PER_TX" \
  GAS_LIMIT="$GAS_LIMIT" \
  BENCH_ROOT_DIR_BASE="$BENCH_ROOT_DIR_BASE" \
  BENCH_OUTPUT_DIR_BASE="$BENCH_OUTPUT_DIR_BASE" \
  GETH_BIN="$GETH_BIN" \
  "$ROOT_DIR/run-bench-geth-kv-both.sh"

  python3 "$ROOT_DIR/scripts/kv-db-summary.py" \
    --leveldb-dir "${BENCH_OUTPUT_DIR_BASE}-leveldb" \
    --treedb-dir "${BENCH_OUTPUT_DIR_BASE}-treedb"
done
