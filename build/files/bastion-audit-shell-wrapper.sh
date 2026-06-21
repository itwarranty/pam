#!/bin/sh
# ForceCommand wrapper for access: audit (read-only session log review).
set -eu

LOG="/var/log/bastion_sessions/audit_session_${USER}_$(date +%Y%m%d_%H%M%S).log"
META="${LOG}.meta"

_write_integrity_sidecar() {
  [ -f "${LOG}" ] || return 0
  sha256sum "${LOG}" > "${LOG}.sha256"
  UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  CLIENT="${SSH_CLIENT:-unknown}"
  printf 'SHA256=%s  UTC=%s  USER=%s  ROLE=audit  CLIENT=%s\n' \
    "$(sha256sum "${LOG}" | awk '{print $1}')" \
    "${UTC}" "${USER}" "${CLIENT}" > "${META}"
  chattr +a "${LOG}.sha256" 2>/dev/null || true
  chattr +a "${META}" 2>/dev/null || true
}

trap '_write_integrity_sidecar' EXIT

touch "${LOG}"
chattr +a "${LOG}" 2>/dev/null || true

logger -t bastion "audit session start user=${USER} log=${LOG} client=${SSH_CLIENT:-unknown}"
exec script -q -f -c "/usr/local/bin/bastion-audit-shell.sh" "${LOG}"
