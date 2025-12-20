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
name: Transfer-only execution speed (geth only)
description: |
  Basic Transfer Benchmark - Simple baseline performance test for quick client comparison and CI/CD performance regression testing.

  This benchmark provides a straightforward transfer-only transaction test with multiple gas limits (15M - 90M) to establish baseline performance metrics for Geth.

  Use Case: Quick client comparison, CI/CD performance regression testing, baseline performance measurement, and initial validation of client performance characteristics.

payloads:
  - name: Transfer-only execution speed
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
        value: 10
      - type: gas_limit
        values:
          - 20000000
          - 30000000
          - 60000000
          - 90000000
EOF

"$ROOT_DIR/bin/base-bench" run \
  --config "$TMP_CONFIG" \
  --root-dir "$BENCH_ROOT_DIR" \
  --output-dir "$BENCH_OUTPUT_DIR" \
  --geth-bin "$GETH_BIN"
