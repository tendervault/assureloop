#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify an AssureLoop evidence bundle end to end."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
from typing import Any

from validate_manifest import load_json, validate


DEFAULT_SCHEMA = Path("schemas/release-manifest.schema.json")
REQUIRED_EVIDENCE_FILES = [
    "requirements.yml",
    "test-matrix.yml",
    "security-checklist.yml",
    "release-evidence-template.md",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_windows_absolute_path(path_text: str) -> bool:
    return re.match(r"^[A-Za-z]:[\\/]", path_text) is not None


def is_manifest_path_absolute(path_text: str) -> bool:
    return Path(path_text).is_absolute() or is_windows_absolute_path(path_text)


def sanitized_absolute_path(path_text: str) -> Path:
    sanitized = path_text.replace("\\", "/").replace(":", "")
    return Path(sanitized.lstrip("/"))


def bundle_artifact_path(bundle_root: Path, path_text: str) -> Path:
    if is_manifest_path_absolute(path_text):
        return bundle_root / "artifacts" / "absolute" / sanitized_absolute_path(path_text)
    return bundle_root / "artifacts" / Path(path_text)


def artifact_candidates(path_text: str, bundle_root: Path, base_dir: Path) -> tuple[list[Path], list[Path]]:
    bundle_candidates = [
        bundle_artifact_path(bundle_root, path_text),
        bundle_root / Path(path_text),
    ]

    if is_manifest_path_absolute(path_text):
        base_candidates = [Path(path_text)] if Path(path_text).is_absolute() else []
    else:
        base_candidates = [base_dir / Path(path_text)]

    return bundle_candidates, base_candidates


def choose_artifact_path(path_text: str, bundle_root: Path, base_dir: Path) -> Path | None:
    bundle_candidates, base_candidates = artifact_candidates(path_text, bundle_root, base_dir)

    for candidate in bundle_candidates:
        if candidate.is_file():
            return candidate
    for candidate in base_candidates:
        if candidate.is_file():
            return candidate
    return None


def safe_extract_tar(archive: Path, destination: Path) -> Path:
    destination_resolved = destination.resolve()
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            member_path = Path(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise ValueError(f"archive member escapes extraction directory: {member.name}")
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination_resolved):
                raise ValueError(f"archive member escapes extraction directory: {member.name}")
        try:
            tar.extractall(destination, filter="data")
        except TypeError:
            tar.extractall(destination)

    if (destination / "release-manifest.json").is_file():
        return destination

    top_dirs = [path for path in destination.iterdir() if path.is_dir()]
    if len(top_dirs) == 1 and (top_dirs[0] / "release-manifest.json").is_file():
        return top_dirs[0]

    manifests = list(destination.rglob("release-manifest.json"))
    if len(manifests) == 1:
        return manifests[0].parent

    return destination


def load_bundle_root(bundle: Path, temp_root: Path | None) -> Path:
    if bundle.is_dir():
        return bundle
    if bundle.is_file() and tarfile.is_tarfile(bundle):
        if temp_root is None:
            raise ValueError("internal error: archive extraction directory was not provided")
        return safe_extract_tar(bundle, temp_root)
    raise ValueError(f"bundle must be a directory or tar archive: {bundle}")


def verify_signature(manifest: Path, signature: Path, public_key: Path, openssl: str) -> tuple[bool, str]:
    result = subprocess.run(
        [
            openssl,
            "dgst",
            "-sha256",
            "-verify",
            str(public_key),
            "-signature",
            str(signature),
            str(manifest),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = (result.stdout + result.stderr).strip()
    return result.returncode == 0, output


def resolve_optional_path(raw_path: Path | None, bundle_root: Path) -> Path | None:
    if raw_path is None:
        return None
    if raw_path.exists():
        return raw_path
    bundle_path = bundle_root / raw_path
    if bundle_path.exists():
        return bundle_path
    return raw_path


def verify_bundle(
    bundle_root: Path,
    schema: Path,
    base_dir: Path,
    signature: Path | None,
    public_key: Path | None,
    openssl: str,
) -> tuple[dict[str, Any], list[str], bool]:
    errors: list[str] = []
    signature_performed = False

    manifest_path = bundle_root / "release-manifest.json"
    trace_report = bundle_root / "trace-report.json"

    if not manifest_path.is_file():
        return {}, [f"release-manifest.json not found in bundle: {bundle_root}"], signature_performed

    try:
        manifest = load_json(manifest_path, "manifest")
        schema_data = load_json(schema, "schema")
    except SystemExit as exc:
        return {}, [str(exc)], signature_performed

    if not isinstance(schema_data, dict):
        errors.append(f"schema root must be a JSON object: {schema}")
    else:
        for error in validate(manifest, schema_data):
            errors.append(f"manifest schema: {error}")

    if not isinstance(manifest, dict):
        return {}, errors + ["manifest root is not a JSON object"], signature_performed

    if not trace_report.is_file():
        errors.append("trace-report.json not found in bundle")

    for evidence_file in REQUIRED_EVIDENCE_FILES:
        if not (bundle_root / evidence_file).is_file():
            errors.append(f"required evidence file not found in bundle: {evidence_file}")

    artifacts = manifest.get("artifacts", [])
    if not isinstance(artifacts, list):
        artifacts = []
        errors.append("manifest artifacts field is not a list")

    for index, item in enumerate(artifacts):
        if not isinstance(item, dict):
            errors.append(f"artifact {index} is not an object")
            continue

        path_text = item.get("path")
        expected_sha = item.get("sha256")
        expected_size = item.get("size_bytes")
        kind = item.get("kind")
        if not isinstance(path_text, str) or not isinstance(expected_sha, str):
            errors.append(f"artifact {index} is missing path or sha256")
            continue

        resolved = choose_artifact_path(path_text, bundle_root, base_dir)
        if resolved is None:
            errors.append(f"missing artifact: {path_text}")
            continue

        actual_sha = sha256_file(resolved)
        if actual_sha != expected_sha:
            errors.append(
                f"hash mismatch for {path_text}: expected {expected_sha}, got {actual_sha}"
            )

        if isinstance(expected_size, int) and resolved.stat().st_size != expected_size:
            errors.append(
                f"size mismatch for {path_text}: expected {expected_size}, got {resolved.stat().st_size}"
            )

        if kind == "sbom":
            sbom_path = bundle_root / "sbom" / Path(path_text).name
            if not sbom_path.is_file():
                errors.append(f"missing SBOM file in bundle: sbom/{Path(path_text).name}")
            elif sha256_file(sbom_path) != expected_sha:
                errors.append(f"hash mismatch for SBOM bundle copy: sbom/{Path(path_text).name}")

    signature_path = resolve_optional_path(signature, bundle_root)
    public_key_path = resolve_optional_path(public_key, bundle_root)
    if signature_path or public_key_path:
        signature_performed = True
        if not signature_path or not public_key_path:
            errors.append("--signature and --public-key must be supplied together")
        elif not signature_path.is_file():
            errors.append(f"signature file not found: {signature_path}")
        elif not public_key_path.is_file():
            errors.append(f"public key file not found: {public_key_path}")
        else:
            ok, output = verify_signature(manifest_path, signature_path, public_key_path, openssl)
            if not ok:
                errors.append(f"signature verification failed: {output}")

    return manifest, errors, signature_performed


def print_summary(manifest: dict[str, Any], errors: list[str], signature_performed: bool) -> None:
    artifacts = manifest.get("artifacts", []) if isinstance(manifest, dict) else []
    if not isinstance(artifacts, list):
        artifacts = []

    sbom_count = sum(
        1 for item in artifacts if isinstance(item, dict) and item.get("kind") == "sbom"
    )

    print(f"product: {manifest.get('product', 'unknown')}")
    print(f"version: {manifest.get('version', 'unknown')}")
    print(f"target: {manifest.get('target', 'unknown')}")
    print(f"artifact_count: {len(artifacts)}")
    print(f"sbom_artifact_count: {sbom_count}")
    print(f"signature_verification: {'performed' if signature_performed else 'skipped'}")
    print(f"result: {'PASS' if not errors else 'FAIL'}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--signature", type=Path)
    parser.add_argument("--public-key", type=Path)
    parser.add_argument("--openssl", default="openssl")
    args = parser.parse_args(argv)

    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    try:
        temp_dir = tempfile.TemporaryDirectory()
        bundle_root = load_bundle_root(args.bundle, Path(temp_dir.name))
        manifest, errors, signature_performed = verify_bundle(
            bundle_root=bundle_root,
            schema=args.schema,
            base_dir=Path.cwd().resolve(),
            signature=args.signature,
            public_key=args.public_key,
            openssl=str(args.openssl),
        )
    except (OSError, tarfile.TarError, ValueError) as exc:
        manifest = {}
        errors = [str(exc)]
        signature_performed = False
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)

    print_summary(manifest, errors, signature_performed)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
