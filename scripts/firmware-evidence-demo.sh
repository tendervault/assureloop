#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
WEST="${WEST:-west}"
BUILD_DIR="${BUILD_DIR:-build}"
OUTPUT_DIR="${FIRMWARE_RELEASE_DIR:-dist/firmware-release}"
PRODUCT="${ASSURELOOP_PRODUCT:-assureloop-controller-demo}"
VERSION="${ASSURELOOP_VERSION:-0.1.0-dev}"
TARGET="${ASSURELOOP_TARGET:-qemu_cortex_m3}"
BUILD_PROFILE="${ASSURELOOP_BUILD_PROFILE:-dev}"
TRACE_LOG="${ASSURELOOP_TRACE_LOG:-samples/logs/qemu_controller_boot.log}"
EVIDENCE_NOTE="${ASSURELOOP_EVIDENCE_NOTE:-}"
GENERATE_SBOM=0

usage() {
  cat <<'EOF'
usage: scripts/firmware-evidence-demo.sh [--generate-sbom]

Environment overrides:
  PYTHON, WEST, BUILD_DIR, FIRMWARE_RELEASE_DIR, ASSURELOOP_PRODUCT,
  ASSURELOOP_VERSION, ASSURELOOP_TARGET, ASSURELOOP_BUILD_PROFILE,
  ASSURELOOP_TRACE_LOG, ASSURELOOP_EVIDENCE_NOTE
EOF
}

while (($#)); do
  case "$1" in
    --generate-sbom)
      GENERATE_SBOM=1
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

build_root="${BUILD_DIR%/}"
zephyr_build="${build_root}/zephyr"
if [[ ! -d "${zephyr_build}" ]]; then
  echo "Zephyr build directory not found: ${zephyr_build}. Run a Zephyr build for the target first." >&2
  exit 1
fi

artifact_args=()
bundle_include_args=()
found_firmware_image=0

include_artifact() {
  local filename="$1"
  local kind="$2"
  local firmware="$3"
  local artifact_path="${zephyr_build}/${filename}"

  if [[ -f "${artifact_path}" ]]; then
    artifact_args+=(--artifact "${artifact_path}:${kind}")
    if [[ "${firmware}" == "true" ]]; then
      found_firmware_image=1
    fi
    echo "including ${artifact_path} as ${kind}"
  fi
}

include_artifact "zephyr.signed.bin" "firmware-signed-image" "true"
include_artifact "zephyr.signed.hex" "firmware-signed-image" "true"
include_artifact "zephyr.signed.confirmed.bin" "firmware-signed-image" "true"
include_artifact "zephyr.signed.confirmed.hex" "firmware-signed-image" "true"
include_artifact "zephyr.elf" "firmware-elf" "true"
include_artifact "zephyr.bin" "firmware-bin" "true"
include_artifact "zephyr.hex" "firmware-hex" "true"
include_artifact "zephyr.map" "firmware-map" "false"
include_artifact ".config" "firmware-config" "false"
include_artifact "zephyr.dts" "firmware-devicetree" "false"

if ((${#artifact_args[@]} == 0)); then
  echo "No Zephyr build artifacts found in ${zephyr_build}." >&2
  exit 1
fi

if ((found_firmware_image == 0)); then
  echo "No firmware image artifact found in ${zephyr_build}; expected zephyr.elf or zephyr.bin." >&2
  exit 1
fi

if ((GENERATE_SBOM)); then
  if command -v "${WEST}" >/dev/null 2>&1; then
    west_cmd=("${WEST}")
  elif [[ "${WEST}" == "west" ]] && "${PYTHON}" -m west --version >/dev/null 2>&1; then
    west_cmd=("${PYTHON}" -m west)
  else
    echo "Zephyr SBOM generation failed: west was not found. Activate the Zephyr Python environment, set WEST, or make sure '${PYTHON} -m west' works." >&2
    exit 1
  fi

  echo "initializing Zephyr SPDX metadata in ${build_root}"
  "${west_cmd[@]}" spdx --init --build-dir "${build_root}"

  echo "refreshing existing Zephyr build metadata in ${build_root}"
  "${west_cmd[@]}" build -d "${build_root}" -c

  echo "generating Zephyr SPDX/SBOM output in ${build_root}"
  "${west_cmd[@]}" spdx --build-dir "${build_root}"

  sbom_root="${build_root}/spdx"
  if [[ ! -d "${sbom_root}" ]]; then
    echo "Zephyr SBOM generation completed, but ${sbom_root} was not created." >&2
    exit 1
  fi

  sbom_count=0
  while IFS= read -r sbom_file; do
    artifact_args+=(--artifact "${sbom_file}:sbom")
    sbom_count=$((sbom_count + 1))
    echo "including ${sbom_file} as sbom"
  done < <(
    find "${sbom_root}" -type f \( \
      -name '*.spdx' -o \
      -name '*.spdx.*' -o \
      -name '*.sbom' -o \
      -name '*.sbom.*' -o \
      -name '*.cdx' -o \
      -name '*.cdx.*' \
    \) | sort
  )

  if ((sbom_count == 0)); then
    echo "Zephyr SBOM generation completed, but no SPDX/SBOM files were found under ${sbom_root}." >&2
    exit 1
  fi
fi

mkdir -p "${OUTPUT_DIR}"

manifest="${OUTPUT_DIR}/release-manifest.json"
signature="${OUTPUT_DIR}/release-manifest.sig"
trace_report="${OUTPUT_DIR}/trace-report.json"
evidence_bundle="${OUTPUT_DIR}/evidence-bundle"
evidence_archive="${evidence_bundle}.tar.gz"

if [[ ! -f "${TRACE_LOG}" ]]; then
  echo "Trace log not found: ${TRACE_LOG}" >&2
  exit 1
fi

rm -f "${signature}"

if [[ -z "${EVIDENCE_NOTE}" ]]; then
  if [[ "${TARGET}" == "qemu_cortex_m3" ]]; then
    EVIDENCE_NOTE="Simulator qemu_cortex_m3 firmware evidence bundle. Not a certification package."
  else
    EVIDENCE_NOTE="Firmware evidence bundle for ${TARGET}. Development evidence only; not a certification package."
  fi
fi

"${PYTHON}" tools/generate_release_manifest.py \
  --product "${PRODUCT}" \
  --version "${VERSION}" \
  --target "${TARGET}" \
  --build-profile "${BUILD_PROFILE}" \
  --note "${EVIDENCE_NOTE}" \
  "${artifact_args[@]}" \
  --output "${manifest}"

"${PYTHON}" tools/validate_manifest.py --manifest "${manifest}"

"${PYTHON}" tools/generate_trace_report.py \
  --input "${TRACE_LOG}" \
  --output "${trace_report}"

rm -rf "${evidence_bundle}"
rm -f "${evidence_archive}"

"${PYTHON}" tools/build_evidence_bundle.py \
  --manifest "${manifest}" \
  --trace-report "${trace_report}" \
  --evidence-dir evidence \
  --output-dir "${evidence_bundle}" \
  "${bundle_include_args[@]}"
