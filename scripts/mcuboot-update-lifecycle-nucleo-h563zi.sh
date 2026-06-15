#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Builds a local MCUboot update-lifecycle investigation for ST NUCLEO-H563ZI.
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
IMGTOOL="${IMGTOOL:-imgtool}"
BASELINE_BUILD_DIR="${MCUBOOT_NUCLEO_H563ZI_BASELINE_BUILD_DIR:-build-mcuboot-lifecycle-nucleo-h563zi-baseline}"
UPDATE_BUILD_DIR="${MCUBOOT_NUCLEO_H563ZI_UPDATE_BUILD_DIR:-build-mcuboot-lifecycle-nucleo-h563zi-update}"
KEYS_DIR="${ASSURELOOP_KEYS_DIR:-keys}"
KEY_FILE="${ASSURELOOP_MCUBOOT_KEY:-}"
SERIAL_PORT="${ASSURELOOP_NUCLEO_SERIAL_PORT:-COM4}"
BAUD="${ASSURELOOP_NUCLEO_BAUD:-115200}"
BASELINE_VERSION="0.1.0-dev"
UPDATE_VERSION="0.1.1-dev"
BASELINE_IMAGE_VERSION="0.1.0+0"
UPDATE_IMAGE_VERSION="0.1.1+0"
CONFIRM_UPDATE=0
PERMANENT_UPGRADE=0
FLASH=0

usage() {
  cat <<'EOF'
usage: scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh [--flash] [--confirm-update] [--permanent-upgrade]

Builds a swap-using-offset MCUboot baseline image and a secondary-slot
AssureLoop update image for ST NUCLEO-H563ZI. Flashing is skipped unless
--flash is provided.

Options:
  --flash                         Flash the secondary update image, then baseline MCUboot/app
  --confirm-update                Build the update image to confirm itself on first boot
  --permanent-upgrade             Baseline requests a permanent upgrade instead of test upgrade
  --baseline-version <version>    Release version printed by the baseline app
  --update-version <version>      Release version printed by the update app
  --baseline-image-version <ver>  MCUboot image version for the baseline, e.g. 0.1.0+0
  --update-image-version <ver>    MCUboot image version for the update, e.g. 0.1.1+0

Environment overrides:
  PYTHON, WEST, IMGTOOL, MCUBOOT_NUCLEO_H563ZI_BASELINE_BUILD_DIR,
  MCUBOOT_NUCLEO_H563ZI_UPDATE_BUILD_DIR, ASSURELOOP_KEYS_DIR,
  ASSURELOOP_MCUBOOT_KEY, ZEPHYR_SDK_INSTALL_DIR,
  ASSURELOOP_NUCLEO_SERIAL_PORT, ASSURELOOP_NUCLEO_BAUD
EOF
}

while (($#)); do
  case "$1" in
    --flash)
      FLASH=1
      shift
      ;;
    --confirm-update)
      CONFIRM_UPDATE=1
      shift
      ;;
    --permanent-upgrade)
      PERMANENT_UPGRADE=1
      shift
      ;;
    --baseline-version)
      BASELINE_VERSION="$2"
      shift 2
      ;;
    --update-version)
      UPDATE_VERSION="$2"
      shift 2
      ;;
    --baseline-image-version)
      BASELINE_IMAGE_VERSION="$2"
      shift 2
      ;;
    --update-image-version)
      UPDATE_IMAGE_VERSION="$2"
      shift 2
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

sysbuild_conf="${KEYS_DIR}/mcuboot-nucleo-h563zi-update-lifecycle-sysbuild.conf"
cat >"${sysbuild_conf}" <<EOF
# SPDX-License-Identifier: Apache-2.0
# Generated by scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh; ignored development config.
SB_CONFIG_BOOT_SIGNATURE_KEY_FILE="${key_for_cmake}"
SB_CONFIG_MCUBOOT_MODE_OVERWRITE_ONLY=n
SB_CONFIG_MCUBOOT_MODE_SWAP_USING_OFFSET=y
EOF

baseline_app_conf="${KEYS_DIR}/mcuboot-nucleo-h563zi-lifecycle-baseline.conf"
cat >"${baseline_app_conf}" <<EOF
# SPDX-License-Identifier: Apache-2.0
# Generated baseline app config for local MCUboot update lifecycle investigation.
CONFIG_FLASH=y
CONFIG_FLASH_MAP=y
CONFIG_STREAM_FLASH=y
CONFIG_IMG_MANAGER=y
CONFIG_MCUBOOT_IMG_MANAGER=y
CONFIG_REBOOT=y
CONFIG_BUILD_OUTPUT_BIN=y
CONFIG_BUILD_OUTPUT_HEX=y
CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT=y
CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION="${BASELINE_IMAGE_VERSION}"
EOF
if ((PERMANENT_UPGRADE)); then
  echo "CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_PERMANENT=y" >>"${baseline_app_conf}"
fi

update_app_conf="${KEYS_DIR}/mcuboot-nucleo-h563zi-lifecycle-update.conf"
cat >"${update_app_conf}" <<EOF
# SPDX-License-Identifier: Apache-2.0
# Generated update app config for local MCUboot update lifecycle investigation.
CONFIG_BOOTLOADER_MCUBOOT=y
CONFIG_FLASH=y
CONFIG_FLASH_MAP=y
CONFIG_STREAM_FLASH=y
CONFIG_IMG_MANAGER=y
CONFIG_MCUBOOT_IMG_MANAGER=y
CONFIG_BUILD_OUTPUT_BIN=y
CONFIG_BUILD_OUTPUT_HEX=y
CONFIG_MCUBOOT_BOOTLOADER_MODE_OVERWRITE_ONLY=n
CONFIG_MCUBOOT_BOOTLOADER_MODE_SWAP_USING_OFFSET=y
CONFIG_MCUBOOT_BOOTLOADER_NO_DOWNGRADE=y
CONFIG_ASSURELOOP_NUCLEO_H563ZI_SECONDARY_SLOT_UPDATE_IMAGE=y
CONFIG_MCUBOOT_SIGNATURE_KEY_FILE="${key_for_cmake}"
CONFIG_MCUBOOT_IMGTOOL_SIGN_VERSION="${UPDATE_IMAGE_VERSION}"
EOF
if ((CONFIRM_UPDATE)); then
  echo "CONFIG_ASSURELOOP_MCUBOOT_CONFIRM_ON_BOOT=y" >>"${update_app_conf}"
fi

sysbuild_conf_for_cmake="$(to_cmake_path "${sysbuild_conf}")"
baseline_app_conf_for_cmake="$(to_cmake_path "${baseline_app_conf}")"
update_app_conf_for_cmake="$(to_cmake_path "${update_app_conf}")"

"${west_cmd[@]}" build -p always -b nucleo_h563zi firmware/app -d "${BASELINE_BUILD_DIR}" --sysbuild -- \
  -DFILE_SUFFIX=nucleo_h563zi \
  "-DIMGTOOL:FILEPATH=${imgtool_for_cmake}" \
  "-DSB_EXTRA_CONF_FILE=${sysbuild_conf_for_cmake}" \
  "-DEXTRA_CONF_FILE=${baseline_app_conf_for_cmake}" \
  "-DASSURELOOP_VERSION=${BASELINE_VERSION}"

"${west_cmd[@]}" build -p always -b nucleo_h563zi firmware/app -d "${UPDATE_BUILD_DIR}" -- \
  "-DIMGTOOL:FILEPATH=${imgtool_for_cmake}" \
  "-DEXTRA_CONF_FILE=${update_app_conf_for_cmake}" \
  "-DASSURELOOP_VERSION=${UPDATE_VERSION}"

update_signed_hex="${UPDATE_BUILD_DIR}/zephyr/zephyr.signed.hex"
if [[ ! -f "${BASELINE_BUILD_DIR}/mcuboot/zephyr/zephyr.hex" ]]; then
  echo "No MCUboot bootloader artifact was produced under ${BASELINE_BUILD_DIR}." >&2
  exit 1
fi
if [[ ! -f "${update_signed_hex}" ]]; then
  echo "No secondary-slot signed update hex was produced at ${update_signed_hex}." >&2
  exit 1
fi

echo "MCUboot mode: swap using offset"
echo "bootloader address: 0x08000000"
echo "primary slot address: 0x08010000"
echo "secondary slot address: 0x08100000"
echo "secondary update image start: 0x08102000"
echo "baseline release version: ${BASELINE_VERSION} image version: ${BASELINE_IMAGE_VERSION}"
echo "update release version: ${UPDATE_VERSION} image version: ${UPDATE_IMAGE_VERSION}"
if ((PERMANENT_UPGRADE)); then
  echo "baseline upgrade request mode: permanent"
else
  echo "baseline upgrade request mode: test"
fi
if ((CONFIRM_UPDATE)); then
  echo "update auto-confirm: enabled"
else
  echo "update auto-confirm: disabled"
fi

for artifact in \
  "${BASELINE_BUILD_DIR}/mcuboot/zephyr/zephyr.elf" \
  "${BASELINE_BUILD_DIR}/mcuboot/zephyr/zephyr.hex" \
  "${BASELINE_BUILD_DIR}/mcuboot/zephyr/zephyr.map"; do
  [[ -f "${artifact}" ]] && echo "MCUboot bootloader artifact: ${artifact}"
done

find "${BASELINE_BUILD_DIR}/app/zephyr" -maxdepth 1 -type f \( \
  -name 'zephyr.elf' -o -name 'zephyr.map' -o \
  -name 'zephyr.bin' -o -name 'zephyr.hex' -o \
  -name 'zephyr.signed.bin' -o -name 'zephyr.signed.hex' \
\) -print | sort | sed 's/^/baseline artifact: /'

find "${UPDATE_BUILD_DIR}/zephyr" -maxdepth 1 -type f \( \
  -name 'zephyr.elf' -o -name 'zephyr.map' -o \
  -name 'zephyr.bin' -o -name 'zephyr.hex' -o \
  -name 'zephyr.signed.bin' -o -name 'zephyr.signed.hex' \
\) -print | sort | sed 's/^/secondary-slot update artifact: /'

if ((FLASH)); then
  STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -d "${update_signed_hex}" -v -rst
  echo "secondary update image flashed from ${update_signed_hex}"

  "${west_cmd[@]}" flash -d "${BASELINE_BUILD_DIR}"
  echo "baseline bootloader and primary app flashed. The baseline app will request the staged update on boot."
  echo "Capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
  echo "Expected lifecycle logs include MCUboot swap output, release version=${UPDATE_VERSION}, and loop_summary."
else
  echo "flash skipped. Re-run with --flash to program a connected ST NUCLEO-H563ZI."
  echo "With --flash, the script flashes the secondary update image before the baseline image."
  echo "Capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
fi
