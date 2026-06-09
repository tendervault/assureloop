#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate a simple trace report from AssureLoop runtime logs."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import statistics

JITTER_RE = re.compile(r"\bjitter_ns=(-?\d+)\b")
SUMMARY_RE = re.compile(r"\bloop_summary\b(?P<body>.*)$")


def percentile(values: list[int], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    k = (len(ordered) - 1) * pct
    lower = int(k)
    upper = min(lower + 1, len(ordered) - 1)
    weight = k - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def parse_log(text: str) -> dict[str, object]:
    jitters = [int(match.group(1)) for match in JITTER_RE.finditer(text)]
    abs_jitters = [abs(value) for value in jitters]
    summary_line = None
    for line in text.splitlines():
        if SUMMARY_RE.search(line):
            summary_line = line.strip()

    return {
        "schema_version": "0.1.0",
        "samples": len(jitters),
        "jitter_ns": {
            "min": min(jitters) if jitters else 0,
            "max": max(jitters) if jitters else 0,
            "avg": statistics.fmean(jitters) if jitters else 0.0,
            "avg_abs": statistics.fmean(abs_jitters) if abs_jitters else 0.0,
            "p95_abs": percentile(abs_jitters, 0.95),
        },
        "summary_line": summary_line,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    report = parse_log(args.input.read_text(encoding="utf-8"))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
