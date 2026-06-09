# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]


class ReleaseToolsTest(unittest.TestCase):
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
        powershell = shutil.which("powershell") or shutil.which("pwsh")
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
            for filename, contents in artifacts.items():
                self.assertIn(filename, by_name)
                self.assertEqual(by_name[filename]["sha256"], hashlib.sha256(contents).hexdigest())


if __name__ == "__main__":
    unittest.main()
