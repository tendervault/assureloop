#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Create a simulator-first AssureLoop firmware update package."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import tarfile
import tempfile
from typing import Any

from verify_evidence_bundle import load_bundle_root


DEFAULT_OUTPUT_DIR = Path("dist/firmware-release/update-package")
PREFERRED_FIRMWARE_KINDS = [
    "firmware-signed-image",
    "firmware-bin",
    "firmware-elf",
    "firmware",
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def generated_at() -> str:
    return (
        dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"ERROR: release manifest not found: {path}") from None
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: release manifest is not valid JSON: {path}:{exc.lineno}:{exc.colno}: {exc.msg}"
        ) from None

    if not isinstance(manifest, dict):
        raise SystemExit(f"ERROR: release manifest root must be a JSON object: {path}")
    return manifest


def resolve_manifest_artifact(path_text: str, base_dir: Path) -> Path:
    path = Path(path_text)
    return path if path.is_absolute() else base_dir / path


def select_payload(manifest: dict[str, Any], base_dir: Path, explicit_payload: Path | None) -> tuple[Path, str]:
    if explicit_payload is not None:
        payload = explicit_payload if explicit_payload.is_absolute() else base_dir / explicit_payload
        if not payload.is_file():
            raise SystemExit(f"ERROR: firmware payload not found: {payload}")
        return payload, "firmware-payload"

    artifacts = manifest.get("artifacts", [])
    if not isinstance(artifacts, list):
        raise SystemExit("ERROR: release manifest artifacts field is not a list")

    by_kind: dict[str, list[dict[str, Any]]] = {}
    for item in artifacts:
        if isinstance(item, dict) and isinstance(item.get("kind"), str):
            by_kind.setdefault(item["kind"], []).append(item)

    for kind in PREFERRED_FIRMWARE_KINDS:
        for item in by_kind.get(kind, []):
            path_text = item.get("path")
            if not isinstance(path_text, str):
                continue
            payload = resolve_manifest_artifact(path_text, base_dir)
            if payload.is_file():
                return payload, kind

    raise SystemExit(
        "ERROR: no firmware payload found. Pass --payload or include a firmware-bin/firmware-elf artifact in the release manifest."
    )


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_tree_files(source_dir: Path, destination_dir: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    if not source_dir.is_dir():
        return records

    for source in sorted(path for path in source_dir.rglob("*") if path.is_file()):
        relative = source.relative_to(source_dir)
        destination = destination_dir / relative
        copy_file(source, destination)
        records.append(
            {
                "path": destination.relative_to(destination_dir.parent).as_posix(),
                "size_bytes": destination.stat().st_size,
                "sha256": sha256_file(destination),
            }
        )
    return records


def evidence_archive_source(evidence_bundle: Path) -> Path:
    if evidence_bundle.is_file():
        return evidence_bundle

    archive = evidence_bundle.with_suffix(".tar.gz")
    if archive.is_file():
        return archive

    raise SystemExit(
        f"ERROR: evidence bundle archive not found. Expected {archive} next to {evidence_bundle}."
    )


def reset_output_dir(output_dir: Path) -> None:
    if not output_dir.exists():
        output_dir.mkdir(parents=True)
        return

    if not output_dir.is_dir():
        raise SystemExit(f"ERROR: update package output path is not a directory: {output_dir}")

    if output_dir.name != "update-package" and not (output_dir / "update-package.json").is_file():
        raise SystemExit(
            f"ERROR: refusing to replace output directory without update-package marker: {output_dir}"
        )

    shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)


def build_package(args: argparse.Namespace) -> Path:
    manifest_path = args.manifest.resolve()
    manifest = load_manifest(manifest_path)
    base_dir = Path.cwd().resolve()
    output_dir = args.output_dir.resolve()

    temp_dir: tempfile.TemporaryDirectory[str] | None = None
    try:
        temp_dir = tempfile.TemporaryDirectory()
        evidence_root = load_bundle_root(args.evidence_bundle, Path(temp_dir.name))

        trace_source = evidence_root / "trace-report.json"
        if not trace_source.is_file():
            raise SystemExit(f"ERROR: trace-report.json not found in evidence bundle: {evidence_root}")

        archive_source = evidence_archive_source(args.evidence_bundle)
        payload_source, payload_kind = select_payload(manifest, base_dir, args.payload)

        reset_output_dir(output_dir)

        payload_destination = output_dir / "payload" / payload_source.name
        copy_file(payload_source, payload_destination)
        copy_file(manifest_path, output_dir / "release-manifest.json")
        copy_file(trace_source, output_dir / "trace-report.json")
        copy_file(archive_source, output_dir / "evidence-bundle.tar.gz")

        sbom_files = copy_tree_files(evidence_root / "sbom", output_dir / "sbom")

        signing_metadata_record: dict[str, Any] | None = None
        if args.signing_metadata is not None:
            signing_metadata = (
                args.signing_metadata
                if args.signing_metadata.is_absolute()
                else base_dir / args.signing_metadata
            )
            if not signing_metadata.is_file():
                raise SystemExit(f"ERROR: signing metadata not found: {signing_metadata}")
            signing_destination = output_dir / "signing" / signing_metadata.name
            copy_file(signing_metadata, signing_destination)
            signing_metadata_record = {
                "path": signing_destination.relative_to(output_dir).as_posix(),
                "size_bytes": signing_destination.stat().st_size,
                "sha256": sha256_file(signing_destination),
            }

        payload_relative = payload_destination.relative_to(output_dir).as_posix()
        package = {
            "schema_version": "0.1.0",
            "package_type": "assureloop-simulator-update",
            "product": manifest.get("product"),
            "version": args.version or manifest.get("version"),
            "min_version": args.min_version,
            "target": manifest.get("target"),
            "generated_at": generated_at(),
            "payload": {
                "path": payload_relative,
                "kind": payload_kind,
                "size_bytes": payload_destination.stat().st_size,
                "sha256": sha256_file(payload_destination),
            },
            "release_manifest": "release-manifest.json",
            "trace_report": "trace-report.json",
            "evidence_bundle": "evidence-bundle.tar.gz",
            "sbom_files": sbom_files,
            "signing_metadata": signing_metadata_record,
            "notes": [
                "Simulator-first update package for development verification.",
                "Not an OTA transport, MCUboot image, production signing model, or certification package.",
            ],
        }

        package_path = output_dir / "update-package.json"
        package_path.write_text(json.dumps(package, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        return package_path
    except (OSError, tarfile.TarError, ValueError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--evidence-bundle", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--payload", type=Path)
    parser.add_argument("--version")
    parser.add_argument("--min-version")
    parser.add_argument("--signing-metadata", type=Path)
    args = parser.parse_args(argv)

    package_path = build_package(args)
    print(f"wrote {package_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
