#!/usr/bin/env bash
# Promote standby bastion to primary (manual HA failover).
set -euo pipefail

CONTAINER="${BASTION_CONTAINER_NAME:-mt_ssh_bastion}"
BASTION_USER="${BASTION_USER:-mt_bastion}"

echo "[ha-promote] Starting ${CONTAINER} on this host..."
sudo -u "${BASTION_USER}" podman start "${CONTAINER}" || podman start "${CONTAINER}"
echo "[ha-promote] Verify: bastion-session-ctl list; update VIP/DNS to this host."
echo "[ha-promote] Active sessions on former primary are lost — operators reconnect."
