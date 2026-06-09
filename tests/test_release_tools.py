# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]


class ReleaseToolsTest(unittest.TestCase):
    def _powershell(self) -> str | None:
        return shutil.which("powershell") or shutil.which("pwsh")

    def _write_fake_openssl(self, work: Path) -> Path:
        fake_impl = work / "fake_openssl.py"
        fake_impl.write_text(
            "\n".join(
                [
                    "from pathlib import Path",
                    "import sys",
                    "",
                    "args = sys.argv[1:]",
                    "",
                    "def value_after(flag):",
                    "    if flag not in args:",
                    "        return None",
                    "    index = args.index(flag)",
                    "    if index + 1 >= len(args):",
                    "        return None",
                    "    return args[index + 1]",
                    "",
                    "if not args:",
                    "    sys.exit(1)",
                    "",
                    "command = args[0]",
                    "if command == 'genpkey':",
                    "    out = value_after('-out')",
                    "    if out is None:",
                    "        sys.exit(2)",
                    "    Path(out).write_text('FAKE PRIVATE KEY\\n', encoding='utf-8')",
                    "    sys.exit(0)",
                    "if command == 'rsa':",
                    "    out = value_after('-out')",
                    "    if out is None:",
                    "        sys.exit(2)",
                    "    Path(out).write_text('FAKE PUBLIC KEY\\n', encoding='utf-8')",
                    "    sys.exit(0)",
                    "if command == 'dgst' and '-verify' in args:",
                    "    print('Verified OK')",
                    "    sys.exit(0)",
                    "if command == 'dgst':",
                    "    out = value_after('-out')",
                    "    if out is None:",
                    "        sys.exit(2)",
                    "    Path(out).write_bytes(b'fake-signature')",
                    "    sys.exit(0)",
                    "",
                    "sys.exit(3)",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        if os.name == "nt":
            fake_openssl = work / "openssl.cmd"
            fake_openssl.write_text(
                f'@echo off\r\n"{sys.executable}" "%~dp0fake_openssl.py" %*\r\n',
                encoding="utf-8",
            )
        else:
            fake_openssl = work / "openssl"
            fake_openssl.write_text(
                f'#!/usr/bin/env sh\n"{sys.executable}" "$(dirname "$0")/fake_openssl.py" "$@"\n',
                encoding="utf-8",
            )
            fake_openssl.chmod(0o755)
        return fake_openssl

    def _make_evidence_bundle(
        self, work: Path, *, include_sbom: bool = True
    ) -> tuple[Path, Path, Path]:
        base = work / "repo"
        zephyr_build = base / "build" / "zephyr"
        zephyr_build.mkdir(parents=True)
        (zephyr_build / "zephyr.elf").write_bytes(b"fake-zephyr-elf")

        artifact_args = ["--artifact", "build/zephyr/zephyr.elf:firmware-elf"]
        if include_sbom:
            spdx_dir = base / "build" / "spdx"
            spdx_dir.mkdir(parents=True)
            (spdx_dir / "app.spdx").write_bytes(
                b"SPDXVersion: SPDX-2.3\nDocumentName: app\n"
            )
            artifact_args += ["--artifact", "build/spdx/app.spdx:sbom"]

        out_dir = base / "dist" / "firmware-release"
        manifest = out_dir / "release-manifest.json"
        trace_report = out_dir / "trace-report.json"
        bundle = out_dir / "evidence-bundle"

        subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tools/generate_release_manifest.py"),
                "--product",
                "assureloop-controller-demo",
                "--version",
                "0.1.0-test",
                "--target",
                "qemu_cortex_m3",
                "--build-profile",
                "test",
                *artifact_args,
                "--base-dir",
                str(base),
                "--source-date-epoch",
                "0",
                "--output",
                str(manifest),
            ],
            check=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tools/generate_trace_report.py"),
                "--input",
                str(REPO_ROOT / "samples/logs/qemu_controller_boot.log"),
                "--output",
                str(trace_report),
            ],
            check=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tools/build_evidence_bundle.py"),
                "--manifest",
                str(manifest),
                "--trace-report",
                str(trace_report),
                "--evidence-dir",
                str(REPO_ROOT / "evidence"),
                "--output-dir",
                str(bundle),
                "--base-dir",
                str(base),
            ],
            check=True,
        )
        return base, bundle, bundle.with_suffix(".tar.gz")

    def _make_update_package(self, work: Path) -> tuple[Path, Path]:
        base, bundle, _archive = self._make_evidence_bundle(work)
        package_dir = base / "dist" / "firmware-release" / "update-package"

        subprocess.run(
            [
                sys.executable,
                str(REPO_ROOT / "tools/create_update_package.py"),
                "--manifest",
                str(base / "dist" / "firmware-release" / "release-manifest.json"),
                "--evidence-bundle",
                str(bundle),
                "--output-dir",
                str(package_dir),
            ],
            cwd=base,
            check=True,
        )
        return base, package_dir

    def test_manifest_and_verify(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            artifact = work / "firmware.bin"
            artifact.write_bytes(b"assureloop-test-firmware")
            manifest = work / "manifest.json"

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_release_manifest.py"),
                    "--product",
                    "test-product",
                    "--version",
                    "0.0.0-test",
                    "--target",
                    "unit-test",
                    "--artifact",
                    "firmware.bin:firmware",
                    "--base-dir",
                    str(work),
                    "--source-date-epoch",
                    "0",
                    "--output",
                    str(manifest),
                ],
                check=True,
            )

            data = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(data["project"], "AssureLoop")
            self.assertEqual(data["artifacts"][0]["kind"], "firmware")

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/validate_manifest.py"),
                    "--manifest",
                    str(manifest),
                ],
                check=True,
            )

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_release.py"),
                    "--manifest",
                    str(manifest),
                    "--base-dir",
                    str(work),
                ],
                check=True,
            )

            artifact.write_bytes(b"tampered")
            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_release.py"),
                    "--manifest",
                    str(manifest),
                    "--base-dir",
                    str(work),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hash mismatch", result.stderr)

    def test_validate_manifest_accepts_valid_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            artifact = work / "firmware.bin"
            artifact.write_bytes(b"assureloop-test-firmware")
            manifest = work / "manifest.json"

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_release_manifest.py"),
                    "--product",
                    "test-product",
                    "--version",
                    "0.0.0-test",
                    "--target",
                    "unit-test",
                    "--artifact",
                    "firmware.bin:firmware",
                    "--base-dir",
                    str(work),
                    "--source-date-epoch",
                    "0",
                    "--output",
                    str(manifest),
                ],
                check=True,
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/validate_manifest.py"),
                    "--manifest",
                    str(manifest),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("validated", result.stdout)

    def test_validate_manifest_rejects_missing_required_field(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            artifact = work / "firmware.bin"
            artifact.write_bytes(b"assureloop-test-firmware")
            manifest = work / "manifest.json"

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_release_manifest.py"),
                    "--product",
                    "test-product",
                    "--version",
                    "0.0.0-test",
                    "--target",
                    "unit-test",
                    "--artifact",
                    "firmware.bin:firmware",
                    "--base-dir",
                    str(work),
                    "--source-date-epoch",
                    "0",
                    "--output",
                    str(manifest),
                ],
                check=True,
            )

            data = json.loads(manifest.read_text(encoding="utf-8"))
            del data["product"]
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/validate_manifest.py"),
                    "--manifest",
                    str(manifest),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing required property 'product'", result.stderr)

    def test_validate_manifest_rejects_malformed_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            artifact = work / "firmware.bin"
            artifact.write_bytes(b"assureloop-test-firmware")
            manifest = work / "manifest.json"

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_release_manifest.py"),
                    "--product",
                    "test-product",
                    "--version",
                    "0.0.0-test",
                    "--target",
                    "unit-test",
                    "--artifact",
                    "firmware.bin:firmware",
                    "--base-dir",
                    str(work),
                    "--source-date-epoch",
                    "0",
                    "--output",
                    str(manifest),
                ],
                check=True,
            )

            data = json.loads(manifest.read_text(encoding="utf-8"))
            data["artifacts"][0]["sha256"] = "not-a-valid-sha"
            manifest.write_text(json.dumps(data), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/validate_manifest.py"),
                    "--manifest",
                    str(manifest),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("$.artifacts[0].sha256", result.stderr)

    def test_trace_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "trace.json"
            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_trace_report.py"),
                    "--input",
                    str(REPO_ROOT / "samples/logs/controller_boot.log"),
                    "--output",
                    str(out),
                ],
                check=True,
            )
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["samples"], 5)
            self.assertEqual(data["jitter_ns"]["max"], 120000)
            self.assertEqual(data["jitter_ns"]["min"], -20000)

    def test_qemu_trace_report_sample(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "qemu-trace.json"
            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/generate_trace_report.py"),
                    "--input",
                    str(REPO_ROOT / "samples/logs/qemu_controller_boot.log"),
                    "--output",
                    str(out),
                ],
                check=True,
            )
            data = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(data["samples"], 20)
            self.assertEqual(data["jitter_ns"]["min"], 10000000)
            self.assertEqual(data["jitter_ns"]["max"], 10000000)
            self.assertIn("loop_summary", data["summary_line"])

    def test_firmware_evidence_script_with_sample_build_outputs(self) -> None:
        powershell = self._powershell()
        if powershell is None:
            self.skipTest("PowerShell is not available")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            zephyr_build = work / "build" / "zephyr"
            zephyr_build.mkdir(parents=True)

            artifacts = {
                "zephyr.elf": b"fake-zephyr-elf",
                "zephyr.map": b"fake-zephyr-map",
                ".config": b"CONFIG_ASSURELOOP_LOOP_ITERATIONS=20\n",
                "zephyr.dts": b"/dts-v1/;\n",
            }
            for filename, contents in artifacts.items():
                (zephyr_build / filename).write_bytes(contents)

            spdx_dir = work / "build" / "spdx"
            spdx_dir.mkdir()
            (spdx_dir / "app.spdx").write_bytes(b"existing-spdx-not-requested")

            out_dir = work / "dist" / "firmware-release"
            subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(REPO_ROOT / "scripts/firmware-evidence-demo.ps1"),
                    "-Python",
                    sys.executable,
                    "-BuildDir",
                    str(work / "build"),
                    "-OutputDir",
                    str(out_dir),
                ],
                cwd=REPO_ROOT,
                check=True,
            )

            manifest_path = out_dir / "release-manifest.json"
            trace_path = out_dir / "trace-report.json"
            self.assertTrue(manifest_path.exists())
            self.assertTrue(trace_path.exists())
            self.assertTrue((out_dir / "evidence-bundle").is_dir())
            self.assertTrue((out_dir / "evidence-bundle.tar.gz").exists())

            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            by_name = {Path(item["path"]).name: item for item in manifest["artifacts"]}
            self.assertEqual(manifest["target"], "qemu_cortex_m3")
            self.assertNotIn("README.md", by_name)
            self.assertNotIn("app.spdx", by_name)
            self.assertFalse((out_dir / "evidence-bundle" / "sbom").exists())
            for filename, contents in artifacts.items():
                self.assertIn(filename, by_name)
                self.assertEqual(by_name[filename]["sha256"], hashlib.sha256(contents).hexdigest())

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/validate_manifest.py"),
                    "--manifest",
                    str(manifest_path),
                ],
                check=True,
            )

    def test_firmware_evidence_script_includes_generated_sbom_outputs(self) -> None:
        powershell = self._powershell()
        if powershell is None or os.name != "nt":
            self.skipTest("PowerShell on Windows is required for the fake west command")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            zephyr_build = work / "build" / "zephyr"
            zephyr_build.mkdir(parents=True)
            (zephyr_build / "zephyr.elf").write_bytes(b"fake-zephyr-elf")

            spdx_dir = work / "build" / "spdx"
            spdx_dir.mkdir()
            sbom_artifacts = {
                "app.spdx": b"SPDXVersion: SPDX-2.3\nDocumentName: app\n",
                "modules-deps.spdx": b"SPDXVersion: SPDX-2.3\nDocumentName: modules\n",
            }
            for filename, contents in sbom_artifacts.items():
                (spdx_dir / filename).write_bytes(contents)

            fake_west = work / "west.cmd"
            fake_west.write_text("@echo off\r\necho fake west %*\r\nexit /b 0\r\n", encoding="utf-8")

            out_dir = work / "dist" / "firmware-release"
            subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(REPO_ROOT / "scripts/firmware-evidence-demo.ps1"),
                    "-Python",
                    sys.executable,
                    "-West",
                    str(fake_west),
                    "-BuildDir",
                    str(work / "build"),
                    "-OutputDir",
                    str(out_dir),
                    "-GenerateSbom",
                ],
                cwd=REPO_ROOT,
                check=True,
            )

            manifest_path = out_dir / "release-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            by_name = {Path(item["path"]).name: item for item in manifest["artifacts"]}
            self.assertIn("zephyr.elf", by_name)
            for filename, contents in sbom_artifacts.items():
                self.assertIn(filename, by_name)
                self.assertEqual(by_name[filename]["kind"], "sbom")
                self.assertEqual(by_name[filename]["sha256"], hashlib.sha256(contents).hexdigest())
                self.assertTrue((out_dir / "evidence-bundle" / "sbom" / filename).exists())

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_release.py"),
                    "--manifest",
                    str(manifest_path),
                    "--base-dir",
                    str(REPO_ROOT),
                ],
                check=True,
            )

    def test_firmware_evidence_script_signs_manifest_with_dev_key(self) -> None:
        powershell = self._powershell()
        if powershell is None or os.name != "nt":
            self.skipTest("PowerShell on Windows is required for the fake OpenSSL command")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            zephyr_build = work / "build" / "zephyr"
            zephyr_build.mkdir(parents=True)
            (zephyr_build / "zephyr.elf").write_bytes(b"fake-zephyr-elf")

            fake_openssl = self._write_fake_openssl(work)
            out_dir = work / "dist" / "firmware-release"
            keys_dir = work / "keys"

            subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(REPO_ROOT / "scripts/firmware-evidence-demo.ps1"),
                    "-Python",
                    sys.executable,
                    "-OpenSsl",
                    str(fake_openssl),
                    "-KeysDir",
                    str(keys_dir),
                    "-BuildDir",
                    str(work / "build"),
                    "-OutputDir",
                    str(out_dir),
                    "-Sign",
                ],
                cwd=REPO_ROOT,
                check=True,
            )

            manifest_path = out_dir / "release-manifest.json"
            signature_path = out_dir / "release-manifest.sig"
            self.assertTrue(manifest_path.exists())
            self.assertTrue(signature_path.exists())
            self.assertTrue((keys_dir / "dev-rsa-private.pem").exists())
            self.assertTrue((keys_dir / "dev-rsa-public.pem").exists())
            self.assertTrue(
                (out_dir / "evidence-bundle" / "release-manifest.sig").exists()
            )
            self.assertTrue(
                (out_dir / "evidence-bundle" / "signing" / "dev-rsa-public.pem").exists()
            )

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_release.py"),
                    "--manifest",
                    str(manifest_path),
                    "--base-dir",
                    str(REPO_ROOT),
                ],
                check=True,
            )

    def test_firmware_evidence_sign_missing_openssl_fails_clearly(self) -> None:
        powershell = self._powershell()
        if powershell is None:
            self.skipTest("PowerShell is not available")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            zephyr_build = work / "build" / "zephyr"
            zephyr_build.mkdir(parents=True)
            (zephyr_build / "zephyr.elf").write_bytes(b"fake-zephyr-elf")

            result = subprocess.run(
                [
                    powershell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(REPO_ROOT / "scripts/firmware-evidence-demo.ps1"),
                    "-Python",
                    sys.executable,
                    "-OpenSsl",
                    str(work / "missing-openssl.exe"),
                    "-KeysDir",
                    str(work / "keys"),
                    "-BuildDir",
                    str(work / "build"),
                    "-OutputDir",
                    str(work / "dist" / "firmware-release"),
                    "-Sign",
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("OpenSSL was not found", result.stdout + result.stderr)

    def test_verify_evidence_bundle_accepts_valid_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, bundle, archive = self._make_evidence_bundle(Path(tmp))

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("result: PASS", result.stdout)

            archive_result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(archive),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(archive_result.returncode, 0, archive_result.stderr)
            self.assertIn("result: PASS", archive_result.stdout)

    def test_verify_evidence_bundle_missing_manifest_fails_clearly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, bundle, _archive = self._make_evidence_bundle(Path(tmp))
            (bundle / "release-manifest.json").unlink()

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("release-manifest.json not found", result.stderr)
            self.assertIn("result: FAIL", result.stdout)

    def test_verify_evidence_bundle_invalid_manifest_schema_fails_clearly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, bundle, _archive = self._make_evidence_bundle(Path(tmp))
            manifest_path = bundle / "release-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            del manifest["product"]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("manifest schema", result.stderr)
            self.assertIn("missing required property 'product'", result.stderr)

    def test_verify_evidence_bundle_tampered_artifact_fails_hash_check(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, bundle, _archive = self._make_evidence_bundle(Path(tmp))
            (bundle / "artifacts" / "build" / "zephyr" / "zephyr.elf").write_bytes(
                b"tampered"
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("hash mismatch for build/zephyr/zephyr.elf", result.stderr)

    def test_verify_evidence_bundle_missing_sbom_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, bundle, _archive = self._make_evidence_bundle(Path(tmp), include_sbom=True)
            (bundle / "sbom" / "app.spdx").unlink()

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("missing SBOM file in bundle: sbom/app.spdx", result.stderr)

    def test_verify_evidence_bundle_accepts_signed_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _base, bundle, _archive = self._make_evidence_bundle(work)
            fake_openssl = self._write_fake_openssl(work)
            private_key = work / "dev-rsa-private.pem"
            private_key.write_text("FAKE PRIVATE KEY\n", encoding="utf-8")
            public_key = bundle / "signing" / "dev-rsa-public.pem"
            public_key.parent.mkdir()
            public_key.write_text("FAKE PUBLIC KEY\n", encoding="utf-8")
            signature = bundle / "release-manifest.sig"

            subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/sign_release.py"),
                    "--manifest",
                    str(bundle / "release-manifest.json"),
                    "--private-key",
                    str(private_key),
                    "--signature",
                    str(signature),
                    "--openssl",
                    str(fake_openssl),
                ],
                check=True,
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_evidence_bundle.py"),
                    "--bundle",
                    str(bundle),
                    "--signature",
                    str(signature),
                    "--public-key",
                    str(public_key),
                    "--openssl",
                    str(fake_openssl),
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("signature_verification: performed", result.stdout)
            self.assertIn("result: PASS", result.stdout)

    def test_verify_update_package_accepts_valid_package(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                    "--target",
                    "qemu_cortex_m3",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("evidence_bundle_verification: performed", result.stdout)
            self.assertIn("result: PASS", result.stdout)

    def test_verify_update_package_tampered_payload_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))
            package = json.loads((package_dir / "update-package.json").read_text(encoding="utf-8"))
            (package_dir / package["payload"]["path"]).write_bytes(b"tampered")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("payload hash mismatch", result.stderr)

    def test_verify_update_package_missing_payload_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))
            package = json.loads((package_dir / "update-package.json").read_text(encoding="utf-8"))
            (package_dir / package["payload"]["path"]).unlink()

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("payload missing", result.stderr)

    def test_verify_update_package_rejects_downgrade(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                    "--installed-version",
                    "999.0.0",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("downgrade rejected", result.stderr)

    def test_verify_update_package_rejects_target_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                    "--target",
                    "other_target",
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("target mismatch", result.stderr)

    def test_verify_update_package_rejects_bad_evidence_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _base, package_dir = self._make_update_package(Path(tmp))
            (package_dir / "evidence-bundle.tar.gz").write_bytes(b"not-a-tarball")

            result = subprocess.run(
                [
                    sys.executable,
                    str(REPO_ROOT / "tools/verify_update_package.py"),
                    "--package",
                    str(package_dir),
                    "--schema",
                    str(REPO_ROOT / "schemas/release-manifest.schema.json"),
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("evidence bundle verification failed", result.stderr)

    def test_private_keys_and_signatures_are_git_ignored(self) -> None:
        if shutil.which("git") is None:
            self.skipTest("git is not available")

        result = subprocess.run(
            [
                "git",
                "check-ignore",
                "keys/dev-rsa-private.pem",
                "dist/firmware-release/release-manifest.sig",
            ],
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("keys/dev-rsa-private.pem", result.stdout)
        self.assertIn("dist/firmware-release/release-manifest.sig", result.stdout)


if __name__ == "__main__":
    unittest.main()
