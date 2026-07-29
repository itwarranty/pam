#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/topology.env"

for c in router guest-pc target gateway-mock; do
  podman rm -f "${LAB_PREFIX}-${c}" 2>/dev/null || true
done

for n in guest corp dmz; do
  podman network rm "${LAB_PREFIX}-${n}" 2>/dev/null || true
done

printf '[down] guest-wifi lab removed\n'
