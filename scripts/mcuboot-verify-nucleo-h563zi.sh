#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Expected signed application artifacts include zephyr.signed.bin and zephyr.signed.hex.
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
IMGTOOL="${IMGTOOL:-imgtool}"
BUILD_DIR="${MCUBOOT_NUCLEO_H563ZI_BUILD_DIR:-build-mcuboot-nucleo-h563zi}"
KEYS_DIR="${ASSURELOOP_KEYS_DIR:-keys}"
KEY_FILE="${ASSURELOOP_MCUBOOT_KEY:-}"
SERIAL_PORT="${ASSURELOOP_NUCLEO_SERIAL_PORT:-COM4}"
BAUD="${ASSURELOOP_NUCLEO_BAUD:-115200}"
FLASH=0

usage() {
  cat <<'EOF'
usage: scripts/mcuboot-verify-nucleo-h563zi.sh [--flash]

Builds AssureLoop for ST NUCLEO-H563ZI with Zephyr sysbuild and MCUboot.
Flashing is skipped unless --flash is provided.

Environment overrides:
  PYTHON, WEST, IMGTOOL, MCUBOOT_NUCLEO_H563ZI_BUILD_DIR,
  ASSURELOOP_KEYS_DIR, ASSURELOOP_MCUBOOT_KEY, ZEPHYR_SDK_INSTALL_DIR,
  ASSURELOOP_NUCLEO_SERIAL_PORT, ASSURELOOP_NUCLEO_BAUD
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
prepend_if_dir "/c/Program Files/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"
prepend_if_dir "/c/Program Files (x86)/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin"

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

west_cmd=()
if [[ -f "${WEST}" ]]; then
  west_cmd=("${WEST}")
elif command -v "${WEST}" >/dev/null 2>&1; then
  west_cmd=("${WEST}")
elif [[ "${WEST}" == "west" ]] && "${PYTHON}" -m west --version >/dev/null 2>&1; then
  west_cmd=("${PYTHON}" -m west)
else
  echo "west was not found. Activate the Zephyr Python environment, set WEST, or make sure '${PYTHON} -m west' works." >&2
  exit 1
fi

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

if ((FLASH)); then
  require_command STM32_Programmer_CLI "STM32CubeProgrammer CLI was not found. Install STM32CubeProgrammer v2.22.0 or add its bin directory to PATH before flashing."
fi

imgtool_cmd=()
imgtool_script=""
if [[ -f "${IMGTOOL}" ]]; then
  imgtool_script="${IMGTOOL}"
  if [[ "${IMGTOOL}" == *.py ]]; then
    imgtool_cmd=("${PYTHON}" "${IMGTOOL}")
  else
    imgtool_cmd=("${IMGTOOL}")
  fi
elif [[ -f "${repo_root}/../bootloader/mcuboot/scripts/imgtool.py" ]]; then
  imgtool_script="${repo_root}/../bootloader/mcuboot/scripts/imgtool.py"
  imgtool_cmd=("${PYTHON}" "${imgtool_script}")
elif [[ -n "${ZEPHYR_BASE:-}" && -f "$(dirname "${ZEPHYR_BASE}")/bootloader/mcuboot/scripts/imgtool.py" ]]; then
  imgtool_script="$(dirname "${ZEPHYR_BASE}")/bootloader/mcuboot/scripts/imgtool.py"
  imgtool_cmd=("${PYTHON}" "${imgtool_script}")
elif command -v "${IMGTOOL}" >/dev/null 2>&1; then
  imgtool_cmd=("${IMGTOOL}")
  if command -v imgtool.py >/dev/null 2>&1; then
    imgtool_script="$(command -v imgtool.py)"
  fi
else
  echo "MCUboot imgtool was not found. Install imgtool, activate the Zephyr Python environment, or set IMGTOOL to imgtool.py." >&2
  exit 1
fi

if [[ -z "${imgtool_script}" ]]; then
  echo "MCUboot imgtool.py was not found for Zephyr signing. Add the MCUboot module to the Zephyr workspace or set IMGTOOL to imgtool.py." >&2
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
imgtool_for_cmake="$(to_cmake_path "${imgtool_script}")"
sysbuild_key_conf="${KEYS_DIR}/mcuboot-nucleo-h563zi-sysbuild.conf"
cat >"${sysbuild_key_conf}" <<EOF
# SPDX-License-Identifier: Apache-2.0
# Generated by scripts/mcuboot-verify-nucleo-h563zi.sh; ignored development config.
SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="${key_for_cmake}"
EOF
sysbuild_key_conf_for_cmake="$(to_cmake_path "${sysbuild_key_conf}")"

"${west_cmd[@]}" build -p always -b nucleo_h563zi firmware/app -d "${BUILD_DIR}" --sysbuild -- \
  -DFILE_SUFFIX=nucleo_h563zi \
  "-DIMGTOOL:FILEPATH=${imgtool_for_cmake}" \
  "-DSB_EXTRA_CONF_FILE=${sysbuild_key_conf_for_cmake}"

bootloader_artifacts=()
for candidate in \
  "${BUILD_DIR}/mcuboot/zephyr/zephyr.elf" \
  "${BUILD_DIR}/mcuboot/zephyr/zephyr.hex" \
  "${BUILD_DIR}/mcuboot/zephyr/zephyr.map"; do
  if [[ -f "${candidate}" ]]; then
    bootloader_artifacts+=("${candidate}")
  fi
done

mapfile -t signed_artifacts < <(
  find "${BUILD_DIR}" -type f \( \
    -name 'zephyr.signed.bin' -o \
    -name 'zephyr.signed.hex' -o \
    -name 'zephyr.signed.confirmed.bin' -o \
    -name 'zephyr.signed.confirmed.hex' \
  \) | sort
)

merged_artifacts=()
for candidate in "${BUILD_DIR}/merged.hex" "${BUILD_DIR}/merged.bin"; do
  if [[ -f "${candidate}" ]]; then
    merged_artifacts+=("${candidate}")
  fi
done

if ((${#bootloader_artifacts[@]} == 0)); then
  echo "No MCUboot bootloader artifacts were produced under ${BUILD_DIR}." >&2
  exit 1
fi
if ((${#signed_artifacts[@]} == 0)); then
  echo "No signed application image artifacts were produced under ${BUILD_DIR}." >&2
  exit 1
fi

for artifact in "${bootloader_artifacts[@]}"; do
  echo "MCUboot bootloader artifact: ${artifact}"
done
for artifact in "${signed_artifacts[@]}"; do
  echo "signed application artifact: ${artifact}"
done
for artifact in "${merged_artifacts[@]}"; do
  echo "merged flash artifact: ${artifact}"
done

if ((FLASH)); then
  "${west_cmd[@]}" flash -d "${BUILD_DIR}"
  echo "flash complete. Capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
  echo "Expected logs include MCUboot boot output, AssureLoop controller demo booting, release product/version, and loop_summary."
else
  echo "flash skipped. Re-run with --flash to program a connected ST NUCLEO-H563ZI."
  echo "After flashing, capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
fi
