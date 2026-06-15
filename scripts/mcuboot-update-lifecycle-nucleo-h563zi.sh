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
NO_CONFIRM_UPDATE=0
PERMANENT_UPGRADE=0
TAMPER_UPDATE=0
DOWNGRADE_UPDATE=0
ERASE_BEFORE_FLASH=0
FLASH_BASELINE=0
FLASH_UPDATE=0
FLASH=0
BASELINE_VERSION_SET=0
UPDATE_VERSION_SET=0
BASELINE_IMAGE_VERSION_SET=0
UPDATE_IMAGE_VERSION_SET=0

usage() {
  cat <<'EOF'
usage: scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh [--flash-baseline] [--flash-update] [--confirm-update|--no-confirm-update]

Builds a swap-using-offset MCUboot baseline image and a secondary-slot
AssureLoop update image for ST NUCLEO-H563ZI. Flashing is skipped unless
--flash is provided.

Options:
  --flash                         Flash the secondary update image, then baseline MCUboot/app
  --flash-baseline                Flash baseline MCUboot/app only
  --flash-update                  Flash secondary-slot update image only
  --confirm-update                Build the update image to confirm itself on first boot
  --no-confirm-update             Build the update image for rollback validation
  --permanent-upgrade             Baseline requests a permanent upgrade instead of test upgrade
  --tamper-update                 Create and optionally flash a tampered signed update hex
  --downgrade-update              Build a higher-version baseline and lower-version update
  --erase-before-flash            Mass erase the device before flashing lifecycle images
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
    --flash-baseline)
      FLASH_BASELINE=1
      shift
      ;;
    --flash-update)
      FLASH_UPDATE=1
      shift
      ;;
    --confirm-update)
      CONFIRM_UPDATE=1
      shift
      ;;
    --no-confirm-update)
      NO_CONFIRM_UPDATE=1
      shift
      ;;
    --permanent-upgrade)
      PERMANENT_UPGRADE=1
      shift
      ;;
    --tamper-update)
      TAMPER_UPDATE=1
      shift
      ;;
    --downgrade-update)
      DOWNGRADE_UPDATE=1
      shift
      ;;
    --erase-before-flash)
      ERASE_BEFORE_FLASH=1
      shift
      ;;
    --baseline-version)
      BASELINE_VERSION="$2"
      BASELINE_VERSION_SET=1
      shift 2
      ;;
    --update-version)
      UPDATE_VERSION="$2"
      UPDATE_VERSION_SET=1
      shift 2
      ;;
    --baseline-image-version)
      BASELINE_IMAGE_VERSION="$2"
      BASELINE_IMAGE_VERSION_SET=1
      shift 2
      ;;
    --update-image-version)
      UPDATE_IMAGE_VERSION="$2"
      UPDATE_IMAGE_VERSION_SET=1
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

if ((CONFIRM_UPDATE && NO_CONFIRM_UPDATE)); then
  echo "use either --confirm-update or --no-confirm-update, not both" >&2
  exit 2
fi

if ((TAMPER_UPDATE && DOWNGRADE_UPDATE)); then
  echo "use either --tamper-update or --downgrade-update, not both" >&2
  exit 2
fi

if (((TAMPER_UPDATE || DOWNGRADE_UPDATE) && CONFIRM_UPDATE)); then
  echo "negative update validation uses a non-confirming update image; omit --confirm-update" >&2
  exit 2
fi

if ((DOWNGRADE_UPDATE)); then
  ((BASELINE_VERSION_SET)) || BASELINE_VERSION="0.1.1-dev"
  ((BASELINE_IMAGE_VERSION_SET)) || BASELINE_IMAGE_VERSION="0.1.1+0"
  ((UPDATE_VERSION_SET)) || UPDATE_VERSION="0.1.0-dev"
  ((UPDATE_IMAGE_VERSION_SET)) || UPDATE_IMAGE_VERSION="0.1.0+0"
fi

if ((FLASH)); then
  FLASH_BASELINE=1
  FLASH_UPDATE=1
fi

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

if ((FLASH_BASELINE || FLASH_UPDATE)); then
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

tamper_intel_hex() {
  local input_hex="$1"
  local output_hex="$2"
  "${PYTHON}" - "${input_hex}" "${output_hex}" <<'PY'
from pathlib import Path
import sys

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
minimum_address = 0x08102400
extended_address = 0
tampered = False
output_lines = []

for line in input_path.read_text(encoding="utf-8").splitlines():
    if len(line) < 11 or not line.startswith(":"):
        output_lines.append(line)
        continue

    byte_count = int(line[1:3], 16)
    address = int(line[3:7], 16)
    record_type = int(line[7:9], 16)
    data = line[9 : 9 + byte_count * 2]

    if record_type == 4 and byte_count == 2:
        extended_address = int(data, 16) << 16
        output_lines.append(line)
        continue

    if not tampered and record_type == 0 and byte_count:
        absolute_address = extended_address + address
        if absolute_address >= minimum_address:
            data_bytes = bytearray(bytes.fromhex(data))
            data_bytes[0] ^= 0x01
            checksum_sum = (
                byte_count
                + ((address >> 8) & 0xFF)
                + (address & 0xFF)
                + record_type
                + sum(data_bytes)
            )
            checksum = (-checksum_sum) & 0xFF
            output_lines.append(
                f":{byte_count:02X}{address:04X}{record_type:02X}"
                f"{data_bytes.hex().upper()}{checksum:02X}"
            )
            tampered = True
            continue

    output_lines.append(line)

if not tampered:
    raise SystemExit(
        f"could not find an Intel HEX data record at or after "
        f"0x{minimum_address:08X} to tamper in {input_path}"
    )

output_path.write_text("\n".join(output_lines) + "\n", encoding="utf-8")
PY
}

key_for_cmake="$(to_cmake_path "${signing_key}")"
imgtool_for_cmake="$(to_cmake_path "${imgtool_script}")"
BASELINE_ROLE="baseline"
if ((DOWNGRADE_UPDATE)); then
  UPDATE_ROLE="update-downgrade"
elif ((TAMPER_UPDATE)); then
  UPDATE_ROLE="update-tampered"
elif ((CONFIRM_UPDATE)); then
  UPDATE_ROLE="update-confirm"
else
  UPDATE_ROLE="update-rollback"
fi

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
CONFIG_FLASH_PAGE_LAYOUT=y
CONFIG_FLASH_MAP=y
CONFIG_STREAM_FLASH=y
CONFIG_IMG_MANAGER=y
CONFIG_MCUBOOT_IMG_MANAGER=y
CONFIG_REBOOT=y
CONFIG_BUILD_OUTPUT_BIN=y
CONFIG_BUILD_OUTPUT_HEX=y
CONFIG_ASSURELOOP_LIFECYCLE_ROLE="${BASELINE_ROLE}"
CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ON_BOOT=y
CONFIG_ASSURELOOP_MCUBOOT_REQUEST_UPGRADE_ONCE=y
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
CONFIG_FLASH_PAGE_LAYOUT=y
CONFIG_FLASH_MAP=y
CONFIG_STREAM_FLASH=y
CONFIG_IMG_MANAGER=y
CONFIG_MCUBOOT_IMG_MANAGER=y
CONFIG_BUILD_OUTPUT_BIN=y
CONFIG_BUILD_OUTPUT_HEX=y
CONFIG_MCUBOOT_BOOTLOADER_MODE_OVERWRITE_ONLY=n
CONFIG_MCUBOOT_BOOTLOADER_MODE_SWAP_USING_OFFSET=y
CONFIG_MCUBOOT_BOOTLOADER_NO_DOWNGRADE=y
CONFIG_ASSURELOOP_LIFECYCLE_ROLE="${UPDATE_ROLE}"
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
flash_update_hex="${update_signed_hex}"
tampered_update_hex=""
if [[ ! -f "${BASELINE_BUILD_DIR}/mcuboot/zephyr/zephyr.hex" ]]; then
  echo "No MCUboot bootloader artifact was produced under ${BASELINE_BUILD_DIR}." >&2
  exit 1
fi
if [[ ! -f "${update_signed_hex}" ]]; then
  echo "No secondary-slot signed update hex was produced at ${update_signed_hex}." >&2
  exit 1
fi
if ((TAMPER_UPDATE)); then
  tampered_update_hex="${UPDATE_BUILD_DIR}/zephyr/zephyr.signed.tampered.hex"
  tamper_intel_hex "${update_signed_hex}" "${tampered_update_hex}"
  flash_update_hex="${tampered_update_hex}"
fi

echo "MCUboot mode: swap using offset"
echo "bootloader address: 0x08000000"
echo "primary slot address: 0x08010000"
echo "secondary slot address: 0x08100000"
echo "secondary update image start: 0x08102000"
echo "baseline release version: ${BASELINE_VERSION} image version: ${BASELINE_IMAGE_VERSION}"
echo "update release version: ${UPDATE_VERSION} image version: ${UPDATE_IMAGE_VERSION}"
echo "baseline lifecycle role: ${BASELINE_ROLE}"
echo "update lifecycle role: ${UPDATE_ROLE}"
if ((PERMANENT_UPGRADE)); then
  echo "baseline upgrade request mode: permanent"
else
  echo "baseline upgrade request mode: test"
fi
echo "baseline upgrade request guard: one-shot storage marker"
if ((CONFIRM_UPDATE)); then
  echo "update auto-confirm: enabled"
else
  echo "update auto-confirm: disabled"
fi
if ((TAMPER_UPDATE)); then
  echo "negative update mode: tamper"
elif ((DOWNGRADE_UPDATE)); then
  echo "negative update mode: downgrade"
else
  echo "negative update mode: none"
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
if [[ -n "${tampered_update_hex}" && -f "${tampered_update_hex}" ]]; then
  echo "secondary-slot update artifact: ${tampered_update_hex}"
fi

if ((FLASH_BASELINE || FLASH_UPDATE)); then
  if ((ERASE_BEFORE_FLASH)); then
    STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -e all
    echo "device mass erase completed before lifecycle flash."
  fi

  if ((FLASH_UPDATE)); then
    STM32_Programmer_CLI -c port=SWD mode=UR reset=HWrst -d "${flash_update_hex}" -v -rst
    echo "secondary update image flashed from ${flash_update_hex}"
  fi

  if ((FLASH_BASELINE)); then
    "${west_cmd[@]}" flash -d "${BASELINE_BUILD_DIR}"
    echo "baseline bootloader and primary app flashed."
  fi

  if ((FLASH_BASELINE && FLASH_UPDATE)); then
    echo "the staged update was programmed before baseline flash so the baseline's first boot can request it once."
  fi
  echo "Capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
  if ((TAMPER_UPDATE)); then
    echo "Expected tamper logs include MCUboot validation rejection for the secondary image and baseline version=${BASELINE_VERSION} continuing to boot."
  elif ((DOWNGRADE_UPDATE)); then
    echo "Expected downgrade logs include MCUboot downgrade prevention for secondary version=${UPDATE_IMAGE_VERSION} and baseline version=${BASELINE_VERSION} continuing to boot."
  else
    echo "Expected lifecycle logs include lifecycle_role=${BASELINE_ROLE}, mcuboot_update_request_once marker=written, MCUboot swap output, release version=${UPDATE_VERSION}, lifecycle_role=${UPDATE_ROLE}, and loop_summary."
  fi
else
  echo "flash skipped. Re-run with --flash-baseline, --flash-update, or --flash to program a connected ST NUCLEO-H563ZI."
  echo "With --flash, the script flashes the secondary update image before the baseline image."
  if [[ -n "${tampered_update_hex}" ]]; then
    echo "tampered secondary update image: ${tampered_update_hex}"
  fi
  echo "Capture serial logs with: ${PYTHON} -m serial.tools.miniterm ${SERIAL_PORT} ${BAUD}"
fi
