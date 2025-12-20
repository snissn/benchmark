#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GETH_BIN_DEFAULT="/home/mikers/dev/snissn/op-geth/build/bin/geth"
GETH_BIN="${GETH_BIN:-$GETH_BIN_DEFAULT}"
BENCH_ROOT_DIR="${BENCH_ROOT_DIR:-$ROOT_DIR/data-dir}"
BENCH_OUTPUT_DIR="${BENCH_OUTPUT_DIR:-$ROOT_DIR/output}"
CALLS_PER_BLOCK="${CALLS_PER_BLOCK:-5}"
NUM_BLOCKS="${NUM_BLOCKS:-5}"
GAS_PER_TX="${GAS_PER_TX:-2000000}"
GAS_LIMIT="${GAS_LIMIT:-30000000}"
DB_ENGINE="${DB_ENGINE:-leveldb}"
BENCH_NAME="${BENCH_NAME:-KV stress (geth only)}"
BENCH_DESC="${BENCH_DESC:-Storage write (SSTORE) stress test to exercise the key-value database.}"
PAYLOAD_NAME="${PAYLOAD_NAME:-KV stress}"
PAYLOAD_ID="${PAYLOAD_ID:-sstore}"
FUNC_SIGNATURE="${FUNC_SIGNATURE:-writer(uint256,bytes)}"
CALLDATA="${CALLDATA:-0x}"
NODE_ARGS_EXTRA="${NODE_ARGS_EXTRA:-}"

NODE_ARGS="--db.engine=${DB_ENGINE}"
if [[ -n "$NODE_ARGS_EXTRA" ]]; then
  NODE_ARGS="${NODE_ARGS} ${NODE_ARGS_EXTRA}"
fi

if [[ ! -x "$GETH_BIN" ]]; then
  echo "ERROR: geth binary not found or not executable: $GETH_BIN" >&2
  echo "Set GETH_BIN to the correct path." >&2
  exit 1
fi

case "$DB_ENGINE" in
  leveldb|treedb|pebble) ;;
  *)
    echo "ERROR: DB_ENGINE must be one of: leveldb, treedb, pebble" >&2
    exit 1
    ;;
esac

BYTECODE_PATH="$ROOT_DIR/contracts/out/Precompile.sol/Precompile.json"
if [[ ! -f "$BYTECODE_PATH" ]]; then
  if command -v forge >/dev/null 2>&1; then
    (cd "$ROOT_DIR/contracts" && forge build --via-ir --optimize --optimizer-runs 200 --extra-output-files bin --force)
  else
    echo "ERROR: missing $BYTECODE_PATH" >&2
    echo "Install Foundry or run: (cd \"$ROOT_DIR/contracts\" && forge build --via-ir --optimize --optimizer-runs 200 --extra-output-files bin --force)" >&2
    exit 1
  fi
fi

TMP_CONFIG="$(mktemp)"
trap 'rm -f "$TMP_CONFIG"' EXIT

cat >"$TMP_CONFIG" <<EOF
name: "${BENCH_NAME}"
description: |
  ${BENCH_DESC}

payloads:
  - name: "${PAYLOAD_NAME}"
    id: "${PAYLOAD_ID}"
    type: contract
    calls_per_block: ${CALLS_PER_BLOCK}
    function_signature: "${FUNC_SIGNATURE}"
    gas_per_tx: ${GAS_PER_TX}
    calldata: "${CALLDATA}"
    contract_bytecode: Precompile

benchmarks:
  - variables:
      - type: payload
        value: "${PAYLOAD_ID}"
      - type: node_type
        values:
          - geth
      - type: node_args
        value: "${NODE_ARGS}"
      - type: num_blocks
        value: ${NUM_BLOCKS}
      - type: gas_limit
        values:
          - ${GAS_LIMIT}
EOF

"$ROOT_DIR/bin/base-bench" run \
  --config "$TMP_CONFIG" \
  --root-dir "$BENCH_ROOT_DIR" \
  --output-dir "$BENCH_OUTPUT_DIR" \
  --geth-bin "$GETH_BIN"
