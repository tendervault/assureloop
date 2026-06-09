#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
BOARD="${ASSURELOOP_TARGET:-qemu_cortex_m3}"

usage() {
  cat <<'EOF'
usage: scripts/full-demo.sh

Environment overrides:
  PYTHON, WEST, ASSURELOOP_TARGET
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

step() {
  printf '\n==> %s\n' "$1"
}

if ! command -v "${WEST}" >/dev/null 2>&1; then
  echo "west was not found. Activate the Zephyr Python environment or set WEST. See docs/contributor-quickstart.md." >&2
  exit 1
fi

step "Host Python tests"
"${PYTHON}" -m unittest discover -s tests -v

step "Zephyr simulator build check"
"${WEST}" build -b "${BOARD}" firmware/app

step "Signed image demo"
PYTHON="${PYTHON}" WEST="${WEST}" ASSURELOOP_SIGNED_IMAGE_BOARD="${BOARD}" \
  bash scripts/signed-image-demo.sh

step "Firmware evidence with SBOM"
PYTHON="${PYTHON}" WEST="${WEST}" \
  bash scripts/firmware-evidence-demo.sh --generate-sbom

step "Evidence verification"
PYTHON="${PYTHON}" bash scripts/verify-firmware-evidence.sh

step "Update package demo"
PYTHON="${PYTHON}" WEST="${WEST}" ASSURELOOP_TARGET="${BOARD}" \
  bash scripts/update-package-demo.sh

step "OTA simulator demo"
PYTHON="${PYTHON}" ASSURELOOP_TARGET="${BOARD}" \
  bash scripts/ota-sim-demo.sh

printf '\nFull simulator demo completed.\n'
