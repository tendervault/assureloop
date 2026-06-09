#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
BUILD_DIR="${BUILD_DIR:-build}"
FIRMWARE_RELEASE_DIR="${FIRMWARE_RELEASE_DIR:-dist/firmware-release}"
UPDATE_PACKAGE_DIR="${UPDATE_PACKAGE_DIR:-dist/firmware-release/update-package}"
TARGET="${ASSURELOOP_TARGET:-qemu_cortex_m3}"

usage() {
  cat <<'EOF'
usage: scripts/update-package-demo.sh

Environment overrides:
  PYTHON, WEST, BUILD_DIR, FIRMWARE_RELEASE_DIR, UPDATE_PACKAGE_DIR,
  ASSURELOOP_TARGET
EOF
}

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"

zephyr_build="${BUILD_DIR%/}/zephyr"
if [[ ! -d "${zephyr_build}" ]]; then
  echo "Zephyr build directory not found: ${zephyr_build}. Run 'west build -b qemu_cortex_m3 firmware/app' first." >&2
  exit 1
fi

WEST="${WEST}" \
BUILD_DIR="${BUILD_DIR}" \
FIRMWARE_RELEASE_DIR="${FIRMWARE_RELEASE_DIR}" \
"${BASH}" scripts/firmware-evidence-demo.sh --generate-sbom

"${PYTHON}" tools/create_update_package.py \
  --manifest "${FIRMWARE_RELEASE_DIR}/release-manifest.json" \
  --evidence-bundle "${FIRMWARE_RELEASE_DIR}/evidence-bundle" \
  --output-dir "${UPDATE_PACKAGE_DIR}"

"${PYTHON}" tools/verify_update_package.py \
  --package "${UPDATE_PACKAGE_DIR}" \
  --target "${TARGET}"

if "${PYTHON}" tools/verify_update_package.py \
  --package "${UPDATE_PACKAGE_DIR}" \
  --installed-version 999.0.0; then
  echo "downgrade rejection demo unexpectedly passed" >&2
  exit 1
else
  echo "downgrade rejection demo passed"
fi
