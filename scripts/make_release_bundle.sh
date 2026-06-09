#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

BOARD="${1:-qemu_cortex_m3}"
BUILD_DIR="${BUILD_DIR:-build}"
DIST="${DIST:-dist}"
VERSION="${ASSURELOOP_VERSION:-0.1.0-dev}"

mkdir -p "${DIST}/firmware" "${DIST}/sbom"

./scripts/build_firmware.sh "${BOARD}"

for artifact in zephyr.bin zephyr.hex zephyr.elf; do
  if [[ -f "${BUILD_DIR}/zephyr/${artifact}" ]]; then
    cp "${BUILD_DIR}/zephyr/${artifact}" "${DIST}/firmware/${artifact}"
  else
    echo "warning: missing optional firmware artifact ${artifact}" >&2
  fi
done

if command -v west >/dev/null 2>&1; then
  west spdx --init -d "${BUILD_DIR}" || true
  west spdx -d "${BUILD_DIR}" || true
  if [[ -d "${BUILD_DIR}/spdx" ]]; then
    cp "${BUILD_DIR}"/spdx/* "${DIST}/sbom/" 2>/dev/null || true
  fi
fi

ARTIFACT_ARGS=()
for artifact in "${DIST}/firmware"/*; do
  [[ -f "${artifact}" ]] && ARTIFACT_ARGS+=(--artifact "${artifact}:firmware")
done

python3 tools/generate_release_manifest.py \
  --product assureloop-controller-demo \
  --version "${VERSION}" \
  --target "${BOARD}" \
  --build-profile "${ASSURELOOP_BUILD_PROFILE:-dev}" \
  "${ARTIFACT_ARGS[@]}" \
  --sbom-dir "${DIST}/sbom" \
  --output "${DIST}/release-manifest.json"

python3 tools/verify_release.py --manifest "${DIST}/release-manifest.json" --base-dir .

echo "release bundle staged in ${DIST}"
