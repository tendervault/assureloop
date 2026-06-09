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
        fake_openssl = work / "openssl.cmd"
        fake_openssl.write_text(
            f'@echo off\r\n"{sys.executable}" "%~dp0fake_openssl.py" %*\r\n',
            encoding="utf-8",
        )
        return fake_openssl

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
