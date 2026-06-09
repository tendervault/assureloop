#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
IMGTOOL="${IMGTOOL:-imgtool}"
BUILD_DIR="${SIGNED_BUILD_DIR:-build-signed}"
OUTPUT_DIR="${SIGNED_FIRMWARE_RELEASE_DIR:-dist/firmware-signed-release}"
KEYS_DIR="${ASSURELOOP_KEYS_DIR:-keys}"
KEY_FILE="${ASSURELOOP_MCUBOOT_KEY:-}"
BOARD="${ASSURELOOP_SIGNED_IMAGE_BOARD:-qemu_cortex_m3}"
OVERLAY="${ASSURELOOP_SIGNED_IMAGE_OVERLAY:-firmware/app/overlays/qemu_cortex_m3_mcuboot.overlay}"

usage() {
  cat <<'EOF'
usage: scripts/signed-image-demo.sh

Environment overrides:
  PYTHON, WEST, IMGTOOL, SIGNED_BUILD_DIR, SIGNED_FIRMWARE_RELEASE_DIR,
  ASSURELOOP_KEYS_DIR, ASSURELOOP_MCUBOOT_KEY, ASSURELOOP_SIGNED_IMAGE_BOARD,
  ASSURELOOP_SIGNED_IMAGE_OVERLAY
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

if ! command -v "${WEST}" >/dev/null 2>&1; then
  echo "west was not found. Activate the Zephyr Python environment or set WEST." >&2
  exit 1
fi

imgtool_cmd=()
if [[ -f "${IMGTOOL}" ]]; then
  imgtool_cmd=("${IMGTOOL}")
elif command -v "${IMGTOOL}" >/dev/null 2>&1; then
  imgtool_cmd=("${IMGTOOL}")
elif [[ -f "${repo_root}/../bootloader/mcuboot/scripts/imgtool.py" ]]; then
  imgtool_cmd=("${PYTHON}" "${repo_root}/../bootloader/mcuboot/scripts/imgtool.py")
elif [[ -n "${ZEPHYR_BASE:-}" && -f "$(dirname "${ZEPHYR_BASE}")/bootloader/mcuboot/scripts/imgtool.py" ]]; then
  imgtool_cmd=("${PYTHON}" "$(dirname "${ZEPHYR_BASE}")/bootloader/mcuboot/scripts/imgtool.py")
else
  echo "MCUboot imgtool was not found. Install imgtool, activate the Zephyr Python environment, or set IMGTOOL to imgtool.py." >&2
  exit 1
fi

mkdir -p "${KEYS_DIR}"
if [[ -n "${KEY_FILE}" ]]; then
  signing_key="${KEY_FILE}"
else
  signing_key="${KEYS_DIR}/mcuboot-dev-rsa-2048.pem"
fi

if [[ ! -f "${signing_key}" ]]; then
  "${imgtool_cmd[@]}" keygen -k "${signing_key}" -t rsa-2048
  echo "created ${signing_key}"
  echo "development MCUboot key only; do not use for production"
fi

if [[ ! -f "${OVERLAY}" ]]; then
  echo "signed-image overlay not found: ${OVERLAY}" >&2
  exit 1
fi

to_cmake_path() {
  local input="$1"
  local absolute
  if [[ "${input}" = /* ]]; then
    absolute="${input}"
  else
    absolute="${repo_root}/${input}"
  fi

  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "${absolute}"
  else
    realpath "${absolute}"
  fi
}

key_for_cmake="$(to_cmake_path "${signing_key}")"
overlay_for_cmake="$(to_cmake_path "${OVERLAY}")"

"${WEST}" build -p always -b "${BOARD}" firmware/app -d "${BUILD_DIR}" -- \
  -DCONFIG_BOOTLOADER_MCUBOOT=y \
  -DCONFIG_BUILD_OUTPUT_BIN=y \
  "-DCONFIG_MCUBOOT_SIGNATURE_KEY_FILE:STRING=\"${key_for_cmake}\"" \
  "-DEXTRA_DTC_OVERLAY_FILE=${overlay_for_cmake}"

zephyr_build="${BUILD_DIR%/}/zephyr"
signed_artifacts=()
for candidate in \
  "${zephyr_build}/zephyr.signed.bin" \
  "${zephyr_build}/zephyr.signed.hex" \
  "${zephyr_build}/zephyr.signed.confirmed.bin" \
  "${zephyr_build}/zephyr.signed.confirmed.hex"; do
  if [[ -f "${candidate}" ]]; then
    signed_artifacts+=("${candidate}")
  fi
done

if ((${#signed_artifacts[@]} == 0)); then
  echo "No signed image artifacts were produced under ${zephyr_build}." >&2
  exit 1
fi

for artifact in "${signed_artifacts[@]}"; do
  echo "signed image artifact: ${artifact}"
done

if [[ -f "${zephyr_build}/zephyr.signed.bin" ]]; then
  "${imgtool_cmd[@]}" verify -k "${signing_key}" "${zephyr_build}/zephyr.signed.bin"
fi

PYTHON="${PYTHON}" \
WEST="${WEST}" \
BUILD_DIR="${BUILD_DIR}" \
FIRMWARE_RELEASE_DIR="${OUTPUT_DIR}" \
"${BASH}" scripts/firmware-evidence-demo.sh

"${PYTHON}" tools/create_update_package.py \
  --manifest "${OUTPUT_DIR}/release-manifest.json" \
  --evidence-bundle "${OUTPUT_DIR}/evidence-bundle" \
  --output-dir "${OUTPUT_DIR}/update-package"

"${PYTHON}" tools/verify_update_package.py \
  --package "${OUTPUT_DIR}/update-package" \
  --target "${BOARD}"
