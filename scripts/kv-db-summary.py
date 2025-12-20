#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime


def _load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _parse_time(value, fallback_index):
    if not value:
        return datetime.fromtimestamp(fallback_index)
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return datetime.fromtimestamp(fallback_index)


def _pick_run(metadata):
    runs = metadata.get("runs", [])
    if not runs:
        return None
    enriched = []
    for idx, run in enumerate(runs):
        created_at = _parse_time(run.get("createdAt"), idx)
        enriched.append((created_at, idx, run))
    enriched.sort(key=lambda item: item[0])
    # Prefer the most recent successful run.
    for created_at, idx, run in reversed(enriched):
        if run.get("result", {}).get("success") is True:
            return run
    return enriched[-1][2]


def _avg_metrics(metrics, keys):
    totals = {}
    counts = {}
    for entry in metrics:
        data = entry.get("ExecutionMetrics", {})
        for key in keys:
            if key not in data:
                continue
            totals[key] = totals.get(key, 0.0) + float(data[key])
            counts[key] = counts.get(key, 0) + 1
    averages = {}
    for key in keys:
        if counts.get(key, 0) == 0:
            continue
        averages[key] = totals[key] / counts[key]
    return averages


def _fmt(value):
    if value is None:
        return "n/a"
    if abs(value) >= 1000:
        return f"{value:,.2f}"
    return f"{value:.4f}"


def _fmt_percent(value):
    if value is None:
        return "n/a"
    return f"{value:+.2f}%"


def _build_summary(output_dir, label):
    metadata_path = os.path.join(output_dir, "metadata.json")
    if not os.path.isfile(metadata_path):
        raise FileNotFoundError(f"missing {metadata_path}")
    metadata = _load_json(metadata_path)
    run = _pick_run(metadata)
    if run is None:
        raise RuntimeError(f"no runs found in {metadata_path}")
    run_dir = os.path.join(output_dir, run["outputDir"])
    seq_path = os.path.join(run_dir, "metrics-sequencer.json")
    val_path = os.path.join(run_dir, "metrics-validator.json")
    seq_metrics = _load_json(seq_path)
    val_metrics = _load_json(val_path)
    return {
        "label": label,
        "run_id": run.get("id"),
        "run_dir": run_dir,
        "sequencer": seq_metrics,
        "validator": val_metrics,
    }


def _compare_table(title, keys, left, right, unit=None, convert=None):
    lines = [title]
    header = f"{'metric':40} {'leveldb':>14} {'treedb':>14} {'diff':>10}"
    lines.append(header)
    lines.append("-" * len(header))
    left_avg = _avg_metrics(left, keys)
    right_avg = _avg_metrics(right, keys)
    for key in keys:
        lval = left_avg.get(key)
        rval = right_avg.get(key)
        if convert:
            lval = convert(lval) if lval is not None else None
            rval = convert(rval) if rval is not None else None
        diff = None
        if lval is not None and rval is not None and lval != 0:
            diff = (rval - lval) / lval * 100.0
        label = key
        if unit:
            label = f"{key} ({unit})"
        lines.append(f"{label:40} {_fmt(lval):>14} {_fmt(rval):>14} {_fmt_percent(diff):>10}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Compare KV stress metrics for leveldb vs treedb.")
    parser.add_argument("--leveldb-dir", default="output-leveldb", help="Path to leveldb output dir")
    parser.add_argument("--treedb-dir", default="output-treedb", help="Path to treedb output dir")
    args = parser.parse_args()

    leveldb = _build_summary(args.leveldb_dir, "leveldb")
    treedb = _build_summary(args.treedb_dir, "treedb")

    print("KV DB summary (first draft)")
    print(f"leveldb run: {leveldb['run_id']} ({leveldb['run_dir']})")
    print(f"treedb run: {treedb['run_id']} ({treedb['run_dir']})")
    print()

    latency_keys_seq = [
        "latency/send_txs",
        "latency/get_payload",
        "latency/update_fork_choice",
    ]
    perf_keys_seq = [
        "gas/per_second",
        "gas/per_block",
        "transactions/per_block",
    ]
    db_keys_seq = [
        "chain/write.50-percentile",
        "chain/storage/updates.50-percentile",
        "chain/storage/reads.50-percentile",
        "chain/storage/commits.50-percentile",
        "chain/triedb/commits.50-percentile",
        "chain/account/commits.50-percentile",
        "chain/inserts.50-percentile",
        "chain/execution.50-percentile",
    ]

    print(_compare_table(
        "Sequencer performance (avg across blocks)",
        perf_keys_seq,
        leveldb["sequencer"],
        treedb["sequencer"],
    ))
    print()
    print(_compare_table(
        "Sequencer latency (avg, ms; lower is better)",
        latency_keys_seq,
        leveldb["sequencer"],
        treedb["sequencer"],
        unit="ms",
        convert=lambda v: v / 1_000_000.0,
    ))
    print()
    print(_compare_table(
        "Sequencer DB-ish metrics (avg; raw units)",
        db_keys_seq,
        leveldb["sequencer"],
        treedb["sequencer"],
    ))
    print()

    latency_keys_val = [
        "latency/new_payload",
        "latency/update_fork_choice",
    ]
    perf_keys_val = [
        "gas/per_second",
        "gas/per_block",
    ]
    db_keys_val = [
        "chain/write.50-percentile",
        "chain/storage/updates.50-percentile",
        "chain/storage/reads.50-percentile",
        "chain/storage/commits.50-percentile",
        "chain/triedb/commits.50-percentile",
        "chain/account/commits.50-percentile",
        "chain/inserts.50-percentile",
        "chain/execution.50-percentile",
    ]

    print(_compare_table(
        "Validator performance (avg across blocks)",
        perf_keys_val,
        leveldb["validator"],
        treedb["validator"],
    ))
    print()
    print(_compare_table(
        "Validator latency (avg, ms; lower is better)",
        latency_keys_val,
        leveldb["validator"],
        treedb["validator"],
        unit="ms",
        convert=lambda v: v / 1_000_000.0,
    ))
    print()
    print(_compare_table(
        "Validator DB-ish metrics (avg; raw units)",
        db_keys_val,
        leveldb["validator"],
        treedb["validator"],
    ))

    print()
    print("Notes:")
    print("- Diff is treedb vs leveldb (%). Positive means treedb is higher.")
    print("- DB-ish metrics use raw units from geth metrics; treat them as relative indicators.")


if __name__ == "__main__":
    main()
