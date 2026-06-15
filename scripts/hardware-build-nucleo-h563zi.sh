#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-}"
BOARD="${ASSURELOOP_HARDWARE_BOARD:-nucleo_h563zi}"
BUILD_DIR="${ASSURELOOP_HARDWARE_BUILD_DIR:-build-nucleo-h563zi}"
FLASH=0

usage() {
  cat <<'EOF'
usage: scripts/hardware-build-nucleo-h563zi.sh [--flash]

Builds firmware/app for the ST NUCLEO-H563ZI into build-nucleo-h563zi.
Flashing is skipped unless --flash is provided.

Environment overrides:
  PYTHON, WEST, ASSURELOOP_HARDWARE_BOARD, ASSURELOOP_HARDWARE_BUILD_DIR
EOF
}

while (($#)); do
  case "$1" in
    --flash)
      FLASH=1
      ;;
    --board)
      shift
      BOARD="${1:?missing value for --board}"
      ;;
    --build-dir)
      shift
      BUILD_DIR="${1:?missing value for --build-dir}"
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
  shift
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

require_command cmake "CMake was not found. Install CMake and make sure it is on PATH before building Zephyr."
require_command ninja "Ninja was not found. Install Ninja and make sure it is on PATH before building Zephyr."

west_cmd=()
if [[ -n "${WEST}" ]]; then
  if [[ -f "${WEST}" ]]; then
    west_cmd=("${WEST}")
  elif command -v "${WEST}" >/dev/null 2>&1; then
    west_cmd=("${WEST}")
  else
    echo "west was not found at '${WEST}'. Activate the Zephyr Python environment or set WEST." >&2
    exit 1
  fi
elif command -v west >/dev/null 2>&1; then
  west_cmd=(west)
else
  require_command "${PYTHON}" "Python was not found. Install Python or set PYTHON."
  if "${PYTHON}" -m west --version >/dev/null 2>&1; then
    west_cmd=("${PYTHON}" -m west)
  else
    echo "west was not found. Activate the Zephyr Python environment, install west, set WEST, or use '${PYTHON} -m west'." >&2
    exit 1
  fi
fi

"${west_cmd[@]}" build -p always -b "${BOARD}" firmware/app -d "${BUILD_DIR}"
echo "hardware build complete: ${BUILD_DIR}"

if ((FLASH)); then
  "${west_cmd[@]}" flash -d "${BUILD_DIR}"
  echo "flash complete. Open the serial console with: ${PYTHON} -m serial.tools.miniterm COM4 115200"
else
  echo "flash skipped. Re-run with --flash to program a connected ST NUCLEO-H563ZI."
fi
