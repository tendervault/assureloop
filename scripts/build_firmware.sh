#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

BOARD="${1:-qemu_cortex_m3}"
BUILD_DIR="${BUILD_DIR:-build}"
GIT_SHA="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"

west build -d "${BUILD_DIR}" -b "${BOARD}" firmware/app -- \
  -DASSURELOOP_GIT_SHA="${GIT_SHA}" \
  -DASSURELOOP_VERSION="${ASSURELOOP_VERSION:-0.1.0-dev}" \
  -DASSURELOOP_BUILD_PROFILE="${ASSURELOOP_BUILD_PROFILE:-dev}"
