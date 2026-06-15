#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
IMGTOOL="${IMGTOOL:-imgtool}"
BUILD_DIR="${SIGNED_NUCLEO_H563ZI_BUILD_DIR:-build-signed-nucleo-h563zi}"
OUTPUT_DIR="${SIGNED_NUCLEO_H563ZI_RELEASE_DIR:-dist/firmware-nucleo-h563zi-release}"
KEYS_DIR="${ASSURELOOP_KEYS_DIR:-keys}"
KEY_FILE="${ASSURELOOP_MCUBOOT_KEY:-}"
TRACE_LOG="${ASSURELOOP_NUCLEO_TRACE_LOG:-samples/logs/nucleo_h563zi_boot.log}"
FLASH=0

usage() {
  cat <<'EOF'
usage: scripts/signed-image-demo-nucleo-h563zi.sh [--flash]

Builds the ST NUCLEO-H563ZI signed-image evidence release.
Flashing is skipped unless --flash is provided.

Environment overrides:
  PYTHON, WEST, IMGTOOL, SIGNED_NUCLEO_H563ZI_BUILD_DIR,
  SIGNED_NUCLEO_H563ZI_RELEASE_DIR, ASSURELOOP_KEYS_DIR,
  ASSURELOOP_MCUBOOT_KEY, ZEPHYR_SDK_INSTALL_DIR, ASSURELOOP_NUCLEO_TRACE_LOG
EOF
}

while (($#)); do
  case "$1" in
    --flash)
      FLASH=1
      shift
      ;;
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

require_command() {
  local command_name="$1"
  local message="$2"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "${message}" >&2
    exit 1
  fi
}

prepend_if_dir() {
  local candidate="$1"
  if [[ -d "${candidate}" ]]; then
    PATH="${candidate}:${PATH}"
    export PATH
  fi
}

prepend_if_dir "/c/Program Files/CMake/bin"
prepend_if_dir "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja"

if ! command -v "${WEST}" >/dev/null 2>&1; then
  user_base="$("${PYTHON}" -c 'import site; print(site.USER_BASE)' 2>/dev/null || true)"
  if [[ -n "${user_base}" ]]; then
    prepend_if_dir "${user_base}/Scripts"
    if command -v cygpath >/dev/null 2>&1; then
      prepend_if_dir "$(cygpath -u "${user_base}")/Scripts"
    fi
  fi
fi

require_command cmake "CMake was not found. Install CMake and make sure it is on PATH before building Zephyr."
require_command ninja "Ninja was not found. Install Ninja and make sure it is on PATH before building Zephyr."

if [[ -z "${ZEPHYR_SDK_INSTALL_DIR:-}" ]]; then
  if [[ -d /d/zephyr-sdk && "$(uname -s)" == MINGW* ]]; then
    ZEPHYR_SDK_INSTALL_DIR="D:\\zephyr-sdk"
  else
    echo "Zephyr SDK was not found. Set ZEPHYR_SDK_INSTALL_DIR, for example D:\\zephyr-sdk." >&2
    exit 1
  fi
fi
export ZEPHYR_SDK_INSTALL_DIR
export ZEPHYR_TOOLCHAIN_VARIANT="${ZEPHYR_TOOLCHAIN_VARIANT:-zephyr}"

if [[ -n "${KEY_FILE}" ]]; then
  export ASSURELOOP_MCUBOOT_KEY="${KEY_FILE}"
fi

flash_args=()
if ((FLASH)); then
  flash_args+=(--flash)
fi

PYTHON="${PYTHON}" \
WEST="${WEST}" \
IMGTOOL="${IMGTOOL}" \
SIGNED_BUILD_DIR="${BUILD_DIR}" \
SIGNED_FIRMWARE_RELEASE_DIR="${OUTPUT_DIR}" \
ASSURELOOP_KEYS_DIR="${KEYS_DIR}" \
ASSURELOOP_SIGNED_IMAGE_BOARD="nucleo_h563zi" \
ASSURELOOP_TARGET="nucleo_h563zi" \
ASSURELOOP_TRACE_LOG="${TRACE_LOG}" \
ASSURELOOP_EVIDENCE_NOTE="ST NUCLEO-H563ZI board-specific signed image evidence bundle. Development keys only; not production secure boot or certification." \
ASSURELOOP_SIGNED_IMAGE_OVERLAY="" \
bash scripts/signed-image-demo.sh --generate-sbom "${flash_args[@]}"

"${PYTHON}" tools/verify_evidence_bundle.py \
  --bundle "${OUTPUT_DIR}/evidence-bundle"

"${PYTHON}" tools/verify_update_package.py \
  --package "${OUTPUT_DIR}/update-package" \
  --target nucleo_h563zi

echo "NUCLEO-H563ZI signed evidence release: ${OUTPUT_DIR}"
echo "Evidence bundle: ${OUTPUT_DIR}/evidence-bundle"
echo "Update package: ${OUTPUT_DIR}/update-package"
