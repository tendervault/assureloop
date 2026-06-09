#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Verify a simulator-first AssureLoop firmware update package."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
import tarfile
import tempfile
from typing import Any

from validate_manifest import load_json, validate
from verify_evidence_bundle import load_bundle_root, sha256_file, verify_bundle


DEFAULT_PACKAGE_DIR = Path("dist/firmware-release/update-package")
DEFAULT_SCHEMA = Path("schemas/release-manifest.schema.json")


def load_package(path: Path) -> dict[str, Any]:
    package_path = path / "update-package.json"
    try:
        package = json.loads(package_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"ERROR: update-package.json not found: {package_path}") from None
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: update-package.json is not valid JSON: {package_path}:{exc.lineno}:{exc.colno}: {exc.msg}"
        ) from None

    if not isinstance(package, dict):
        raise SystemExit(f"ERROR: update-package.json root must be a JSON object: {package_path}")
    return package


def package_relative_path(package_dir: Path, value: Any, label: str) -> Path | None:
    if not isinstance(value, str) or not value:
        return None
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{label} must be a package-relative path: {value}")
    return package_dir / path


def version_key(version: str) -> list[tuple[int, int | str]]:
    parts = [part for part in re.split(r"[.+_-]", version) if part]
    key: list[tuple[int, int | str]] = []
    for part in parts:
        if part.isdigit():
            key.append((0, int(part)))
        else:
            key.append((1, part))
    return key


def is_lower_version(candidate: str, installed: str) -> bool:
    candidate_key = version_key(candidate)
    installed_key = version_key(installed)
    max_len = max(len(candidate_key), len(installed_key))
    candidate_key += [(0, 0)] * (max_len - len(candidate_key))
    installed_key += [(0, 0)] * (max_len - len(installed_key))
    return candidate_key < installed_key


def validate_release_manifest(manifest_path: Path, schema_path: Path) -> list[str]:
    errors: list[str] = []
    try:
        manifest = load_json(manifest_path, "release manifest")
        schema = load_json(schema_path, "schema")
    except SystemExit as exc:
        return [str(exc)]

    if not isinstance(schema, dict):
        return [f"schema root must be a JSON object: {schema_path}"]

    for error in validate(manifest, schema):
        errors.append(f"release manifest schema: {error}")
    return errors


def verify_package(
    package_dir: Path,
    schema: Path,
    installed_version: str | None,
    target: str | None,
) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    package = load_package(package_dir)

    payload = package.get("payload")
    if not isinstance(payload, dict):
        errors.append("payload metadata is missing or invalid")
    else:
        try:
            payload_path = package_relative_path(package_dir, payload.get("path"), "payload.path")
        except ValueError as exc:
            payload_path = None
            errors.append(str(exc))

        if payload_path is None:
            errors.append("payload.path is missing")
        elif not payload_path.is_file():
            errors.append(f"payload missing: {payload_path}")
        else:
            expected_sha = payload.get("sha256")
            expected_size = payload.get("size_bytes")
            if not isinstance(expected_sha, str):
                errors.append("payload.sha256 is missing")
            else:
                actual_sha = sha256_file(payload_path)
                if actual_sha != expected_sha:
                    errors.append(
                        f"payload hash mismatch: expected {expected_sha}, got {actual_sha}"
                    )
            if isinstance(expected_size, int) and payload_path.stat().st_size != expected_size:
                errors.append(
                    f"payload size mismatch: expected {expected_size}, got {payload_path.stat().st_size}"
                )

    try:
        manifest_path = package_relative_path(
            package_dir, package.get("release_manifest"), "release_manifest"
        )
    except ValueError as exc:
        manifest_path = None
        errors.append(str(exc))

    if manifest_path is None:
        errors.append("release_manifest is missing")
    elif not manifest_path.is_file():
        errors.append(f"release manifest missing: {manifest_path}")
    else:
        errors.extend(validate_release_manifest(manifest_path, schema))

    try:
        evidence_bundle_path = package_relative_path(
            package_dir, package.get("evidence_bundle"), "evidence_bundle"
        )
    except ValueError as exc:
        evidence_bundle_path = None
        errors.append(str(exc))

    if evidence_bundle_path is None:
        errors.append("evidence_bundle is missing")
    elif not evidence_bundle_path.is_file():
        errors.append(f"evidence bundle missing: {evidence_bundle_path}")
    else:
        temp_dir: tempfile.TemporaryDirectory[str] | None = None
        try:
            temp_dir = tempfile.TemporaryDirectory()
            bundle_root = load_bundle_root(evidence_bundle_path, Path(temp_dir.name))
            _manifest, bundle_errors, _signature_performed = verify_bundle(
                bundle_root=bundle_root,
                schema=schema,
                base_dir=package_dir.resolve(),
                signature=None,
                public_key=None,
                openssl="openssl",
            )
            for error in bundle_errors:
                errors.append(f"evidence bundle verification failed: {error}")
        except (OSError, tarfile.TarError, ValueError) as exc:
            errors.append(f"evidence bundle verification failed: {exc}")
        finally:
            if temp_dir is not None:
                temp_dir.cleanup()

    try:
        trace_report_path = package_relative_path(
            package_dir, package.get("trace_report"), "trace_report"
        )
    except ValueError as exc:
        trace_report_path = None
        errors.append(str(exc))

    if trace_report_path is None:
        errors.append("trace_report is missing")
    elif not trace_report_path.is_file():
        errors.append(f"trace report missing: {trace_report_path}")

    package_version = package.get("version")
    if installed_version is not None:
        if not isinstance(package_version, str):
            errors.append("package version is missing")
        elif is_lower_version(package_version, installed_version):
            errors.append(
                f"downgrade rejected: package version {package_version} is lower than installed version {installed_version}"
            )

    package_target = package.get("target")
    if target is not None and package_target != target:
        errors.append(f"target mismatch: package target {package_target!r} does not match {target!r}")

    return package, errors


def print_summary(package: dict[str, Any], errors: list[str]) -> None:
    payload = package.get("payload", {}) if isinstance(package, dict) else {}
    sbom_files = package.get("sbom_files", []) if isinstance(package, dict) else []
    if not isinstance(sbom_files, list):
        sbom_files = []

    print(f"product: {package.get('product', 'unknown')}")
    print(f"version: {package.get('version', 'unknown')}")
    print(f"target: {package.get('target', 'unknown')}")
    print(f"payload: {payload.get('path', 'unknown') if isinstance(payload, dict) else 'unknown'}")
    print(f"sbom_file_count: {len(sbom_files)}")
    print("evidence_bundle_verification: performed")
    print(f"result: {'PASS' if not errors else 'FAIL'}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE_DIR)
    parser.add_argument("--schema", type=Path, default=DEFAULT_SCHEMA)
    parser.add_argument("--installed-version")
    parser.add_argument("--target")
    args = parser.parse_args(argv)

    package_dir = args.package.resolve()
    try:
        package, errors = verify_package(
            package_dir=package_dir,
            schema=args.schema.resolve(),
            installed_version=args.installed_version,
            target=args.target,
        )
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return 1

    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)

    print_summary(package, errors)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
