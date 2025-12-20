#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GETH_BIN_DEFAULT="/home/mikers/dev/snissn/op-geth/build/bin/geth"
GETH_BIN="${GETH_BIN:-$GETH_BIN_DEFAULT}"
BENCH_ROOT_DIR="${BENCH_ROOT_DIR:-$ROOT_DIR/data-dir}"
BENCH_OUTPUT_DIR="${BENCH_OUTPUT_DIR:-$ROOT_DIR/output}"

if [[ ! -x "$GETH_BIN" ]]; then
  echo "ERROR: geth binary not found or not executable: $GETH_BIN" >&2
  echo "Set GETH_BIN to the correct path." >&2
  exit 1
fi

TMP_CONFIG="$(mktemp)"
trap 'rm -f "$TMP_CONFIG"' EXIT

cat >"$TMP_CONFIG" <<'EOF'
name: Tiny transfer-only benchmark (geth only)
description: |
  Minimal transfer-only benchmark to sanity-check the pipeline quickly.

payloads:
  - name: Tiny transfer-only
    id: transfer-only
    type: transfer-only

benchmarks:
  - variables:
      - type: payload
        value: transfer-only
      - type: node_type
        values:
          - geth
      - type: num_blocks
        value: 2
      - type: gas_limit
        values:
          - 15000000
EOF

"$ROOT_DIR/bin/base-bench" run \
  --config "$TMP_CONFIG" \
  --root-dir "$BENCH_ROOT_DIR" \
  --output-dir "$BENCH_OUTPUT_DIR" \
  --geth-bin "$GETH_BIN"
