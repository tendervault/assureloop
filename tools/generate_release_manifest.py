#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate an AssureLoop release manifest."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Iterable

SCHEMA_URL = "https://assureloop.dev/schemas/release-manifest.v0.json"
SCHEMA_VERSION = "0.1.0"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_output(args: list[str], cwd: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return result.stdout.strip()


def git_metadata(repo_root: Path) -> dict[str, object]:
    commit = git_output(["rev-parse", "HEAD"], repo_root) or "unknown"
    short_commit = git_output(["rev-parse", "--short=12", "HEAD"], repo_root) or "unknown"
    status = git_output(["status", "--porcelain"], repo_root)
    return {
        "commit": commit,
        "short_commit": short_commit,
        "dirty": bool(status),
    }


def parse_artifact(spec: str) -> tuple[Path, str]:
    if ":" in spec:
        raw_path, kind = spec.rsplit(":", 1)
        kind = kind.strip() or "artifact"
    else:
        raw_path = spec
        kind = "artifact"
    return Path(raw_path), kind


def artifact_record(path: Path, kind: str, base_dir: Path) -> dict[str, object]:
    resolved = (base_dir / path).resolve() if not path.is_absolute() else path.resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"artifact does not exist: {path}")
    if not resolved.is_file():
        raise ValueError(f"artifact is not a file: {path}")
    display_path = str(path.as_posix()) if not path.is_absolute() else str(path)
    return {
        "path": display_path,
        "kind": kind,
        "size_bytes": resolved.stat().st_size,
        "sha256": sha256_file(resolved),
    }


def iter_sbom_files(sbom_dir: Path | None, base_dir: Path) -> Iterable[tuple[Path, str]]:
    if sbom_dir is None:
        return []
    resolved = (base_dir / sbom_dir).resolve() if not sbom_dir.is_absolute() else sbom_dir.resolve()
    if not resolved.exists():
        raise FileNotFoundError(f"SBOM directory does not exist: {sbom_dir}")
    if not resolved.is_dir():
        raise ValueError(f"SBOM path is not a directory: {sbom_dir}")
    return [(p.relative_to(base_dir.resolve()) if p.is_relative_to(base_dir.resolve()) else p, "sbom") for p in sorted(resolved.glob("*.spdx*"))]


def generated_at_from_epoch(epoch: int | None) -> str:
    if epoch is None:
        epoch_env = os.getenv("SOURCE_DATE_EPOCH")
        if epoch_env:
            epoch = int(epoch_env)
    if epoch is None:
        return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    return dt.datetime.fromtimestamp(epoch, tz=dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_manifest(args: argparse.Namespace) -> dict[str, object]:
    base_dir = args.base_dir.resolve()
    artifacts: list[dict[str, object]] = []

    for spec in args.artifact:
        path, kind = parse_artifact(spec)
        artifacts.append(artifact_record(path, kind, base_dir))

    for path, kind in iter_sbom_files(args.sbom_dir, base_dir):
        artifacts.append(artifact_record(path, kind, base_dir))

    if not artifacts:
        raise ValueError("no artifacts found after processing --artifact and --sbom-dir")

    return {
        "schema": SCHEMA_URL,
        "schema_version": SCHEMA_VERSION,
        "project": "AssureLoop",
        "product": args.product,
        "version": args.version,
        "target": args.target,
        "build_profile": args.build_profile,
        "generated_at": generated_at_from_epoch(args.source_date_epoch),
        "git": git_metadata(base_dir),
        "artifacts": artifacts,
        "notes": args.note,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--build-profile", default="dev")
    parser.add_argument("--artifact", action="append", default=[], help="Artifact as PATH or PATH:kind")
    parser.add_argument("--sbom-dir", type=Path)
    parser.add_argument("--base-dir", type=Path, default=Path.cwd())
    parser.add_argument("--source-date-epoch", type=int)
    parser.add_argument("--note", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)

    if not args.artifact and args.sbom_dir is None:
        parser.error("at least one --artifact or --sbom-dir is required")

    manifest = build_manifest(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
