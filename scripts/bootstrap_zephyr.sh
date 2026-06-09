#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

if ! command -v west >/dev/null 2>&1; then
  echo "west is not installed. Follow Zephyr's getting-started guide first." >&2
  exit 1
fi

if [[ ! -d .west ]]; then
  west init -l .
fi

west update
west zephyr-export

echo "Zephyr workspace ready"
