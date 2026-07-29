#!/usr/bin/env bash
# Promote standby gateway to primary (manual HA failover).
set -euo pipefail

CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
PAM_USER="${PAM_USER:-gateway}"

echo "[ha-promote] Starting ${CONTAINER} on this host..."
sudo -u "${PAM_USER}" podman start "${CONTAINER}" || podman start "${CONTAINER}"
echo "[ha-promote] Verify: pam-session-ctl list; update VIP/DNS to this host."
echo "[ha-promote] Active sessions on former primary are lost — operators reconnect."
