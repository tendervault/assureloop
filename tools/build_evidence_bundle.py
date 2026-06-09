#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build a starter AssureLoop evidence bundle."""

from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import shutil
import tarfile


def copy_if_exists(src: Path, dst: Path, copied: list[dict[str, str]], label: str) -> None:
    if not src.exists():
        copied.append({"label": label, "source": str(src), "status": "missing"})
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    copied.append({"label": label, "source": str(src), "path": str(dst), "status": "copied"})


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--trace-report", type=Path)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)

    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    copied: list[dict[str, str]] = []

    copy_if_exists(args.manifest, out / "release-manifest.json", copied, "release-manifest")
    if args.trace_report:
        copy_if_exists(args.trace_report, out / "trace-report.json", copied, "trace-report")

    for filename in ["requirements.yml", "test-matrix.yml", "security-checklist.yml", "release-evidence-template.md"]:
        copy_if_exists(args.evidence_dir / filename, out / filename, copied, filename)

    index = {
        "schema_version": "0.1.0",
        "project": "AssureLoop",
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "contents": copied,
        "reviewer_note": "Starter evidence bundle. Not a certification package.",
    }
    (out / "index.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    archive = out.with_suffix(".tar.gz")
    with tarfile.open(archive, "w:gz") as tar:
        tar.add(out, arcname=out.name)

    print(f"wrote {out}")
    print(f"wrote {archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
