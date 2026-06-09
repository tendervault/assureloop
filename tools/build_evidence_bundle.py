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


def safe_bundle_path(out: Path, relative_path: Path) -> Path:
    if relative_path.is_absolute():
        raise ValueError(f"bundle destination must be relative: {relative_path}")
    destination = (out / relative_path).resolve()
    out_resolved = out.resolve()
    if not destination.is_relative_to(out_resolved):
        raise ValueError(f"bundle destination escapes output directory: {relative_path}")
    return destination


def copy_if_exists(src: Path, dst: Path, copied: list[dict[str, str]], label: str) -> None:
    if not src.exists():
        copied.append({"label": label, "source": str(src), "status": "missing"})
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    copied.append({"label": label, "source": str(src), "path": str(dst), "status": "copied"})


def bundle_artifact_destination(path_text: str) -> Path:
    path = Path(path_text)
    if path.is_absolute():
        sanitized = str(path).replace("\\", "/").replace(":", "")
        return Path("artifacts") / "absolute" / sanitized.lstrip("/")
    return Path("artifacts") / Path(path_text)


def copy_manifest_artifacts(manifest: Path, base_dir: Path, out: Path, copied: list[dict[str, str]]) -> None:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    artifacts = data.get("artifacts", [])
    if not isinstance(artifacts, list):
        return

    for item in artifacts:
        if not isinstance(item, dict):
            continue
        path_text = item.get("path")
        kind = item.get("kind", "artifact")
        if not isinstance(path_text, str):
            continue

        source_path = Path(path_text)
        source = source_path if source_path.is_absolute() else base_dir / source_path
        destination = safe_bundle_path(out, bundle_artifact_destination(path_text))
        copy_if_exists(source, destination, copied, f"artifact:{kind}:{path_text}")

        if kind == "sbom":
            sbom_destination = safe_bundle_path(out, Path("sbom") / source_path.name)
            copy_if_exists(source, sbom_destination, copied, f"sbom:{path_text}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--trace-report", type=Path)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--base-dir", type=Path, default=Path.cwd())
    parser.add_argument(
        "--include-file",
        nargs=2,
        action="append",
        default=[],
        metavar=("SOURCE", "DEST"),
        help="Copy SOURCE into the bundle at relative path DEST",
    )
    args = parser.parse_args(argv)

    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    copied: list[dict[str, str]] = []
    base_dir = args.base_dir.resolve()

    copy_if_exists(args.manifest, out / "release-manifest.json", copied, "release-manifest")
    if args.trace_report:
        copy_if_exists(args.trace_report, out / "trace-report.json", copied, "trace-report")
    copy_manifest_artifacts(args.manifest, base_dir, out, copied)

    for filename in ["requirements.yml", "test-matrix.yml", "security-checklist.yml", "release-evidence-template.md"]:
        copy_if_exists(args.evidence_dir / filename, out / filename, copied, filename)

    for source, destination in args.include_file:
        dst = safe_bundle_path(out, Path(destination))
        copy_if_exists(Path(source), dst, copied, destination)

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
