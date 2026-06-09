#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify an AssureLoop release manifest and optional signature."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_artifacts(manifest: dict[str, object], base_dir: Path) -> list[str]:
    errors: list[str] = []
    artifacts = manifest.get("artifacts", [])
    if not isinstance(artifacts, list):
        return ["manifest artifacts field is not a list"]

    for item in artifacts:
        if not isinstance(item, dict):
            errors.append("artifact entry is not an object")
            continue
        rel_path = item.get("path")
        expected_hash = item.get("sha256")
        expected_size = item.get("size_bytes")
        if not isinstance(rel_path, str) or not isinstance(expected_hash, str):
            errors.append(f"invalid artifact entry: {item!r}")
            continue
        path = Path(rel_path)
        resolved = path if path.is_absolute() else base_dir / path
        if not resolved.exists():
            errors.append(f"missing artifact: {rel_path}")
            continue
        actual_hash = sha256_file(resolved)
        if actual_hash != expected_hash:
            errors.append(f"hash mismatch for {rel_path}: expected {expected_hash}, got {actual_hash}")
        if expected_size is not None and resolved.stat().st_size != expected_size:
            errors.append(f"size mismatch for {rel_path}: expected {expected_size}, got {resolved.stat().st_size}")
    return errors


def verify_signature(manifest_path: Path, signature: Path, public_key: Path) -> bool:
    result = subprocess.run(
        [
            "openssl",
            "dgst",
            "-sha256",
            "-verify",
            str(public_key),
            "-signature",
            str(signature),
            str(manifest_path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        return False
    print(result.stdout.strip())
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--base-dir", type=Path, default=Path.cwd())
    parser.add_argument("--signature", type=Path)
    parser.add_argument("--public-key", type=Path)
    args = parser.parse_args(argv)

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    errors = verify_artifacts(manifest, args.base_dir.resolve())

    if args.signature or args.public_key:
        if not args.signature or not args.public_key:
            errors.append("--signature and --public-key must be supplied together")
        elif not verify_signature(args.manifest, args.signature, args.public_key):
            errors.append("signature verification failed")

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print(f"verified {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
