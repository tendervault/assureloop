#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
OUTPUT_DIR="${ASSURELOOP_V03_RELEASE_DIR:-dist/releases/v0.3-hardware-alpha}"

usage() {
  cat <<'EOF'
usage: scripts/prepare-v0.3-release.sh

Environment overrides:
  PYTHON, WEST, ASSURELOOP_V03_RELEASE_DIR

The output contains sample/development artifacts only and never copies keys/.
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

prepend_if_dir() {
  local candidate="$1"
  if [[ -d "${candidate}" ]]; then
    PATH="${candidate}:${PATH}"
    export PATH
  fi
}

step() {
  printf '\n==> %s\n' "$1"
}

copy_checked() {
  local source="$1"
  local destination="$2"
  if [[ ! -f "${source}" ]]; then
    echo "required release material does not exist: ${source}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${destination}")"
  cp -f "${source}" "${destination}"
}

copy_tree_checked() {
  local source="$1"
  local destination="$2"
  if [[ ! -e "${source}" ]]; then
    echo "required release material does not exist: ${source}" >&2
    exit 1
  fi
  mkdir -p "$(dirname "${destination}")"
  rm -rf "${destination}"
  cp -R "${source}" "${destination}"
}

assert_no_private_material() {
  local root="$1"
  local found
  found="$(find "${root}" -type f \( \
    -iname '*private*' -o \
    -iname '*secret*' -o \
    -iname '*key*' -o \
    -iname '*.pem' -o \
    -iname '*.p8' -o \
    -iname '*.p12' \
  \) -print)"
  if [[ -n "${found}" ]]; then
    echo "release output contains private or key-like material:" >&2
    echo "${found}" >&2
    exit 1
  fi
}

assert_dist_output() {
  local output="$1"
  case "${output}" in
    dist|dist/*)
      ;;
    *)
      echo "refusing to write release output outside ignored dist tree: ${output}" >&2
      exit 1
      ;;
  esac
}

write_checksums() {
  local root="$1"
  local checksum_file="${root}/SHA256SUMS.txt"
  rm -f "${checksum_file}"
  (
    cd "${root}"
    find . -type f ! -name SHA256SUMS.txt -print |
      sed 's#^\./##' |
      LC_ALL=C sort |
      while IFS= read -r file; do
        "${PYTHON}" - "$file" <<'PY'
import hashlib
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.as_posix()}")
PY
      done > SHA256SUMS.txt
  )
}

prepend_if_dir "/c/Program Files/CMake/bin"
prepend_if_dir "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja"

step "Host Python tests"
"${PYTHON}" -m unittest discover -s tests -v

step "Full simulator demo"
PYTHON="${PYTHON}" WEST="${WEST}" bash scripts/full-demo.sh

step "NUCLEO-H563ZI hardware build"
PYTHON="${PYTHON}" WEST="${WEST}" bash scripts/hardware-build-nucleo-h563zi.sh

step "NUCLEO-H563ZI signed image evidence"
PYTHON="${PYTHON}" WEST="${WEST}" bash scripts/signed-image-demo-nucleo-h563zi.sh

step "NUCLEO-H563ZI MCUboot verification build"
PYTHON="${PYTHON}" WEST="${WEST}" bash scripts/mcuboot-verify-nucleo-h563zi.sh

step "NUCLEO-H563ZI lifecycle build"
PYTHON="${PYTHON}" WEST="${WEST}" bash scripts/mcuboot-update-lifecycle-nucleo-h563zi.sh

step "Assemble release output"
assert_dist_output "${OUTPUT_DIR}"
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

copy_checked "docs/releases/v0.3-hardware-alpha.md" "${OUTPUT_DIR}/release-notes.md"
copy_checked "docs/v0.3-hardware-alpha-release.md" "${OUTPUT_DIR}/release-readiness.md"

for log in \
  samples/logs/qemu_controller_boot.log \
  samples/logs/nucleo_h563zi_boot.log \
  samples/logs/nucleo_h563zi_mcuboot_update_confirm.log \
  samples/logs/nucleo_h563zi_mcuboot_update_rollback.log \
  samples/logs/nucleo_h563zi_mcuboot_tamper_reject.log \
  samples/logs/nucleo_h563zi_mcuboot_downgrade_reject.log
do
  copy_checked "${log}" "${OUTPUT_DIR}/sample-logs/$(basename "${log}")"
done

sample_root="${OUTPUT_DIR}/sample-dev-artifacts"
copy_tree_checked "dist/firmware-nucleo-h563zi-release/evidence-bundle" "${sample_root}/evidence-bundle"
copy_checked "dist/firmware-nucleo-h563zi-release/evidence-bundle.tar.gz" "${sample_root}/evidence-bundle.tar.gz"
copy_tree_checked "dist/firmware-nucleo-h563zi-release/update-package" "${sample_root}/update-package"

{
  echo "AssureLoop v0.3 hardware-alpha local release verification"
  echo
  echo "This output contains sample/development artifacts only."
  echo "Private keys are intentionally excluded."
  echo
  echo "Evidence bundle verification:"
  "${PYTHON}" tools/verify_evidence_bundle.py \
    --bundle dist/firmware-nucleo-h563zi-release/evidence-bundle
  echo
  echo "Update package verification:"
  "${PYTHON}" tools/verify_update_package.py \
    --package dist/firmware-nucleo-h563zi-release/update-package \
    --target nucleo_h563zi
} > "${OUTPUT_DIR}/verification-summary.txt"

assert_no_private_material "${OUTPUT_DIR}"
write_checksums "${OUTPUT_DIR}"

echo "v0.3 hardware-alpha release output: ${OUTPUT_DIR}"
echo "checksums: ${OUTPUT_DIR}/SHA256SUMS.txt"
