#!/bin/sh
# Обёртка ForceCommand для интерактивных shell-сессий (не для ProxyJump).
set -eu

LOG="/var/log/bastion_sessions/session_${USER}_$(date +%Y%m%d_%H%M%S).log"
META="${LOG}.meta"

_write_integrity_sidecar() {
  [ -f "${LOG}" ] || return 0
  sha256sum "${LOG}" > "${LOG}.sha256"
  UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  INCIDENT="${MT_BASTION_INCIDENT_ID:--}"
  CLIENT="${SSH_CLIENT:-unknown}"
  printf 'SHA256=%s  UTC=%s  USER=%s  INCIDENT=%s  CLIENT=%s\n' \
    "$(sha256sum "${LOG}" | awk '{print $1}')" \
    "${UTC}" "${USER}" "${INCIDENT}" "${CLIENT}" > "${META}"
  chattr +a "${LOG}.sha256" 2>/dev/null || true
  chattr +a "${META}" 2>/dev/null || true
}

trap '_write_integrity_sidecar' EXIT

touch "${LOG}"
chattr +a "${LOG}" 2>/dev/null || true

logger -t mt-bastion "shell session start user=${USER} log=${LOG} client=${SSH_CLIENT:-unknown} incident=${MT_BASTION_INCIDENT_ID:--}"
exec script -q -f -c "/bin/bash --login" "${LOG}"
