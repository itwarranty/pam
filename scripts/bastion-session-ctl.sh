#!/usr/bin/env bash
# Host wrapper — list/kill active gateway sessions via podman exec.
set -euo pipefail

CONTAINER="${BASTION_CONTAINER_NAME:-mt_ssh_bastion}"
BASTION_USER="${BASTION_USER:-mt_bastion}"

if ! command -v podman >/dev/null 2>&1; then
  printf 'ERROR: podman not found\n' >&2
  exit 1
fi

if ! podman ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
  printf 'ERROR: container %s not running\n' "${CONTAINER}" >&2
  exit 1
fi

exec podman exec "${CONTAINER}" /usr/local/bin/bastion-session-ctl-internal "$@"
