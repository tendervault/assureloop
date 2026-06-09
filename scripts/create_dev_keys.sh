#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

mkdir -p keys
PRIVATE_KEY="keys/dev-rsa-private.pem"
PUBLIC_KEY="keys/dev-rsa-public.pem"

if [[ ! -f "${PRIVATE_KEY}" ]]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "${PRIVATE_KEY}"
  chmod 600 "${PRIVATE_KEY}"
fi

openssl rsa -in "${PRIVATE_KEY}" -pubout -out "${PUBLIC_KEY}"

echo "created ${PRIVATE_KEY} and ${PUBLIC_KEY}"
echo "development keys only; do not use for production"
