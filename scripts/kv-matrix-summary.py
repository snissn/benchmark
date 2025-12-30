#!/usr/bin/env python3
import argparse
import json
import os
import re
import statistics
from typing import Dict, List, Optional


METRICS = [
    "gas/per_second",
    "gas/per_block",
    "latency/new_payload",
    "latency/update_fork_choice",
    "engine/forkchoice/total.50-percentile",
    "chain/storage/reads.50-percentile",
    "chain/storage/updates.50-percentile",
    "chain/storage/commits.50-percentile",
]

LATENCY_METRICS = {
    "latency/new_payload",
    "latency/update_fork_choice",
    "engine/forkchoice/total.50-percentile",
    "chain/storage/reads.50-percentile",
    "chain/storage/updates.50-percentile",
    "chain/storage/commits.50-percentile",
}


def _load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _pick_run(metadata: dict) -> Optional[dict]:
    runs = metadata.get("runs", [])
    if not runs:
        return None
    # Prefer the most recent successful run.
    for run in reversed(runs):
        if run.get("result", {}).get("success") is True:
            return run
    return runs[-1]


def _avg_validator_metrics(metrics_path: str) -> Dict[str, float]:
    data = _load_json(metrics_path)
    totals: Dict[str, float] = {}
    counts: Dict[str, int] = {}
    for entry in data:
        em = entry.get("ExecutionMetrics", {})
        for key in METRICS:
            if key not in em:
                continue
            totals[key] = totals.get(key, 0.0) + float(em[key])
            counts[key] = counts.get(key, 0) + 1
    out: Dict[str, float] = {}
    for key, total in totals.items():
        out[key] = total / float(counts[key])
    return out


def _ms(ns: float) -> float:
    return ns / 1e6


def _fmt(v: Optional[float], is_latency: bool) -> str:
    if v is None:
        return "n/a"
    if is_latency:
        return f"{v:.3f}"
    if abs(v) >= 1e9:
        return f"{v/1e9:.3f}B"
    if abs(v) >= 1e6:
        return f"{v/1e6:.3f}M"
    if abs(v) >= 1e3:
        return f"{v/1e3:.3f}K"
    return f"{v:.3f}"


def _pct(delta: Optional[float]) -> str:
    if delta is None:
        return "n/a"
    return f"{delta:+.1f}%"


def _pct_change(new: Optional[float], base: Optional[float]) -> Optional[float]:
    if new is None or base is None or base == 0:
        return None
    return (new - base) / base * 100.0


def main() -> int:
    ap = argparse.ArgumentParser(description="Summarize op-geth KV benchmark matrix outputs.")
    ap.add_argument("--matrix-dir", required=True, help="Path to output/matrix-*/ directory")
    ap.add_argument("--baseline", default="leveldb-hash", help="Baseline label (default: leveldb-hash)")
    args = ap.parse_args()

    matrix_dir = os.path.abspath(args.matrix_dir)
    if not os.path.isdir(matrix_dir):
        raise SystemExit(f"not a directory: {matrix_dir}")

    run_re = re.compile(r"^(?P<label>.+)-r(?P<rep>\d+)$")

    grouped: Dict[str, List[Dict[str, float]]] = {}

    for name in sorted(os.listdir(matrix_dir)):
        sub = os.path.join(matrix_dir, name)
        if not os.path.isdir(sub):
            continue
        m = run_re.match(name)
        if not m:
            continue
        label = m.group("label")
        meta_path = os.path.join(sub, "metadata.json")
        if not os.path.isfile(meta_path):
            continue
        meta = _load_json(meta_path)
        run = _pick_run(meta)
        if not run:
            continue
        run_dir = os.path.join(sub, run["outputDir"])
        metrics_path = os.path.join(run_dir, "metrics-validator.json")
        if not os.path.isfile(metrics_path):
            continue
        avg = _avg_validator_metrics(metrics_path)
        grouped.setdefault(label, []).append(avg)

    if not grouped:
        raise SystemExit(f"no runs found under {matrix_dir}")

    # Compute medians.
    medians: Dict[str, Dict[str, Optional[float]]] = {}
    for label, runs in grouped.items():
        out: Dict[str, Optional[float]] = {}
        for key in METRICS:
            vals = [r[key] for r in runs if key in r]
            if not vals:
                out[key] = None
                continue
            v = statistics.median(vals)
            if key in LATENCY_METRICS:
                v = _ms(v)
            out[key] = v
        medians[label] = out

    baseline = medians.get(args.baseline)

    # Print summary table.
    cols = [
        ("gas/s", "gas/per_second", False),
        ("new_payload(ms)", "latency/new_payload", True),
        ("update_fc(ms)", "latency/update_fork_choice", True),
        ("forkchoice50(ms)", "engine/forkchoice/total.50-percentile", True),
        ("reads50(ms)", "chain/storage/reads.50-percentile", True),
        ("updates50(ms)", "chain/storage/updates.50-percentile", True),
        ("commits50(ms)", "chain/storage/commits.50-percentile", True),
    ]

    print(f"matrix_dir: {matrix_dir}")
    print(f"baseline:   {args.baseline}{'' if baseline else ' (missing!)'}")
    print()

    header = ["config", "reps"] + [c[0] for c in cols]
    widths = [max(6, len(header[0]))] + [4] + [max(12, len(c[0])) for c in cols]

    def fmt_row(items):
        return " ".join(str(item).ljust(w) for item, w in zip(items, widths))

    print(fmt_row(header))
    print("-" * (sum(widths) + len(widths) - 1))

    for label in sorted(medians.keys()):
        runs = grouped[label]
        row = [label, str(len(runs))]
        for _, key, is_latency in cols:
            row.append(_fmt(medians[label].get(key), is_latency))
        print(fmt_row(row))

    if baseline:
        print()
        print("diff vs baseline (positive gas/s is better; negative latency is better)")
        diff_header = ["config"] + [c[0] for c in cols]
        diff_widths = [max(6, len(diff_header[0]))] + [max(12, len(c[0])) for c in cols]

        def fmt_diff_row(items):
            return " ".join(str(item).ljust(w) for item, w in zip(items, diff_widths))

        print(fmt_diff_row(diff_header))
        print("-" * (sum(diff_widths) + len(diff_widths) - 1))

        for label in sorted(medians.keys()):
            row = [label]
            for _, key, is_latency in cols:
                base_val = baseline.get(key)
                cur_val = medians[label].get(key)
                if is_latency:
                    # lower is better
                    delta = _pct_change(cur_val, base_val)
                    if delta is not None:
                        delta = -delta
                    row.append(_pct(delta))
                else:
                    row.append(_pct(_pct_change(cur_val, base_val)))
            print(fmt_diff_row(row))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
