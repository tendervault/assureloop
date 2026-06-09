#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Sign an AssureLoop release manifest using OpenSSL."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--private-key", type=Path, required=True)
    parser.add_argument("--signature", type=Path, required=True)
    parser.add_argument("--openssl", default=os.environ.get("OPENSSL", "openssl"))
    args = parser.parse_args(argv)

    if not args.manifest.exists():
        parser.error(f"manifest does not exist: {args.manifest}")
    if not args.private_key.exists():
        parser.error(f"private key does not exist: {args.private_key}")

    args.signature.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            str(args.openssl),
            "dgst",
            "-sha256",
            "-sign",
            str(args.private_key),
            "-out",
            str(args.signature),
            str(args.manifest),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        return result.returncode

    print(f"signed {args.manifest} -> {args.signature}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
