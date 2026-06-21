#!/usr/bin/env bash
# Подключить уже запущенный ssh_bastion к DMZ-сети lab (опционально).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/topology.env"

CONTAINER="${BASTION_CONTAINER_NAME:-ssh_bastion}"
NET_DMZ="${LAB_PREFIX}-dmz"

podman network exists "${NET_DMZ}" || {
  printf 'Run labs/guest-wifi-segment/scripts/up.sh first\n' >&2
  exit 1
}

podman container exists "${CONTAINER}" || {
  printf 'Container %s not found — deploy bastion first (dev-up / site.yml)\n' "${CONTAINER}" >&2
  exit 1
}

podman network connect "${NET_DMZ}" "${CONTAINER}" 2>/dev/null || true
printf '[attach] %s connected to %s\n' "${CONTAINER}" "${NET_DMZ}"
printf 'From guest PC test: podman exec -it %s-guest-pc ssh -p 2222 ...\n' "${LAB_PREFIX}"
printf 'Set allowed_sources to guest egress %s (not 10.1.13.0/24) if bastion is outside L2 guest VLAN.\n' "${GUEST_EGRESS_PUBLIC_IP}"
