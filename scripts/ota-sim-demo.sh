#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
SIGNED_BUILD_DIR="${SIGNED_BUILD_DIR:-build-signed}"
SIGNED_FIRMWARE_RELEASE_DIR="${SIGNED_FIRMWARE_RELEASE_DIR:-dist/firmware-signed-release}"
OTA_SIM_STATE="${OTA_SIM_STATE:-dist/ota-sim/state.json}"
TARGET="${ASSURELOOP_TARGET:-qemu_cortex_m3}"
INITIAL_VERSION="${ASSURELOOP_INSTALLED_VERSION:-0.0.0}"
KEEP_STATE="${OTA_SIM_KEEP_STATE:-}"

usage() {
  cat <<'EOF'
usage: scripts/ota-sim-demo.sh

Environment overrides:
  PYTHON, SIGNED_BUILD_DIR, SIGNED_FIRMWARE_RELEASE_DIR, OTA_SIM_STATE,
  ASSURELOOP_TARGET, ASSURELOOP_INSTALLED_VERSION, OTA_SIM_KEEP_STATE
EOF
}

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    * )
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${repo_root}"

package_dir="${SIGNED_FIRMWARE_RELEASE_DIR%/}/update-package"
signed_image="${SIGNED_BUILD_DIR%/}/zephyr/zephyr.signed.bin"

is_signed_update_package() {
  local package_json="${package_dir}/update-package.json"
  [[ -f "${package_json}" ]] || return 1
  "${PYTHON}" - "$package_json" "$package_dir" <<'PY'
import json
import sys
from pathlib import Path

package_path = Path(sys.argv[1])
package_dir = Path(sys.argv[2])
try:
    package = json.loads(package_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

payload = package.get("payload")
if not isinstance(payload, dict) or payload.get("kind") != "firmware-signed-image":
    raise SystemExit(1)

payload_path = payload.get("path")
if not isinstance(payload_path, str) or not (package_dir / payload_path).is_file():
    raise SystemExit(1)
PY
}

if [[ ! -f "${signed_image}" ]] || ! is_signed_update_package; then
  PYTHON="${PYTHON}" bash scripts/signed-image-demo.sh
fi

state_path="${OTA_SIM_STATE}"
state_dir="$(dirname "${state_path}")"
mkdir -p "${state_dir}"

generated_root="$(cd "${repo_root}" && mkdir -p dist/ota-sim && cd dist/ota-sim && pwd -P)"
remove_generated_path() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  local absolute
  absolute="$(cd "$(dirname "${path}")" && pwd -P)/$(basename "${path}")"
  case "${absolute}" in
    "${generated_root}"/*) rm -rf "${absolute}" ;;
    *) echo "refusing to remove path outside dist/ota-sim: ${absolute}" >&2; exit 1 ;;
  esac
}

if [[ -z "${KEEP_STATE}" ]]; then
  remove_generated_path "${state_path}"
fi

"${PYTHON}" tools/simulate_ota.py \
  --action stage \
  --package "${package_dir}" \
  --state "${state_path}" \
  --target "${TARGET}" \
  --installed-version "${INITIAL_VERSION}"

"${PYTHON}" tools/simulate_ota.py \
  --action install \
  --state "${state_path}" \
  --target "${TARGET}"

"${PYTHON}" tools/simulate_ota.py \
  --action confirm \
  --state "${state_path}"

if "${PYTHON}" tools/simulate_ota.py \
  --action stage \
  --package "${package_dir}" \
  --state "${state_path}" \
  --target "${TARGET}" \
  --installed-version 999.0.0; then
  echo "downgrade rejection demo unexpectedly passed" >&2
  exit 1
else
  echo "downgrade rejection demo passed"
fi

tampered_package_dir="${state_dir%/}/tampered-update-package"
remove_generated_path "${tampered_package_dir}"
cp -R "${package_dir}" "${tampered_package_dir}"

payload_path="$("${PYTHON}" - "${tampered_package_dir}/update-package.json" <<'PY'
import json
import sys
from pathlib import Path

package = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(package["payload"]["path"])
PY
)"
printf tampered > "${tampered_package_dir}/${payload_path}"

if "${PYTHON}" tools/simulate_ota.py \
  --action stage \
  --package "${tampered_package_dir}" \
  --state "${state_path}" \
  --target "${TARGET}"; then
  echo "tamper rejection demo unexpectedly passed" >&2
  exit 1
else
  echo "tamper rejection demo passed"
fi

"${PYTHON}" tools/simulate_ota.py status --state "${state_path}"
