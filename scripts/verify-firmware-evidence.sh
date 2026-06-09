#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

PYTHON="${PYTHON:-python3}"
BUNDLE="${FIRMWARE_EVIDENCE_BUNDLE:-dist/firmware-release/evidence-bundle}"
SCHEMA="${ASSURELOOP_MANIFEST_SCHEMA:-schemas/release-manifest.schema.json}"
SIGNATURE="${ASSURELOOP_MANIFEST_SIGNATURE:-}"
PUBLIC_KEY="${ASSURELOOP_PUBLIC_KEY:-}"
OPENSSL="${OPENSSL:-openssl}"

usage() {
  cat <<'EOF'
usage: scripts/verify-firmware-evidence.sh [options]

Options:
  --bundle PATH       Evidence bundle directory or evidence-bundle.tar.gz
  --schema PATH       Release manifest schema path
  --signature PATH    Optional release-manifest signature
  --public-key PATH   Optional public key for signature verification
  --openssl PATH      OpenSSL command or full path
  -h, --help          Show this help
EOF
}

while (($#)); do
  case "$1" in
    --bundle)
      if (($# < 2)); then
        echo "--bundle requires a path" >&2
        exit 2
      fi
      BUNDLE="$2"
      shift 2
      ;;
    --schema)
      if (($# < 2)); then
        echo "--schema requires a path" >&2
        exit 2
      fi
      SCHEMA="$2"
      shift 2
      ;;
    --signature)
      if (($# < 2)); then
        echo "--signature requires a path" >&2
        exit 2
      fi
      SIGNATURE="$2"
      shift 2
      ;;
    --public-key)
      if (($# < 2)); then
        echo "--public-key requires a path" >&2
        exit 2
      fi
      PUBLIC_KEY="$2"
      shift 2
      ;;
    --openssl)
      if (($# < 2)); then
        echo "--openssl requires a path" >&2
        exit 2
      fi
      OPENSSL="$2"
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

args=(
  tools/verify_evidence_bundle.py
  --bundle "${BUNDLE}"
  --schema "${SCHEMA}"
  --openssl "${OPENSSL}"
)

if [[ ( -n "${SIGNATURE}" && -z "${PUBLIC_KEY}" ) || ( -n "${PUBLIC_KEY}" && -z "${SIGNATURE}" ) ]]; then
  echo "--signature and --public-key must be supplied together" >&2
  exit 2
fi

if [[ -n "${SIGNATURE}" && -n "${PUBLIC_KEY}" ]]; then
  args+=(--signature "${SIGNATURE}" --public-key "${PUBLIC_KEY}")
fi

"${PYTHON}" "${args[@]}"
