# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

import json
from pathlib import Path
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


if __name__ == "__main__":
    unittest.main()
