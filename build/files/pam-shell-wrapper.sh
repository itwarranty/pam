#!/bin/sh
# Обёртка ForceCommand для интерактивных shell-сессий (не для ProxyJump).
set -eu

_sanitize_incident() {
  printf '%s' "${1}" | tr -cd 'A-Za-z0-9._-' | cut -c1-64
}

INCIDENT_RAW="${PAM_INCIDENT_ID:-}"
INCIDENT_TAG=""
if [ -n "${INCIDENT_RAW}" ] && [ "${INCIDENT_RAW}" != "-" ]; then
  INCIDENT_TAG="$(_sanitize_incident "${INCIDENT_RAW}")"
fi

TS="$(date +%Y%m%d_%H%M%S)"
if [ -n "${INCIDENT_TAG}" ]; then
  LOG="/var/log/pam_sessions/session_${INCIDENT_TAG}_${USER}_${TS}.log"
else
  LOG="/var/log/pam_sessions/session_${USER}_${TS}.log"
fi
META="${LOG}.meta"

_write_integrity_sidecar() {
  [ -f "${LOG}" ] || return 0
  sha256sum "${LOG}" > "${LOG}.sha256"
  UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  INCIDENT="${PAM_INCIDENT_ID:--}"
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

BG_LOG=""
[ "${PAM_BREAK_GLASS:-0}" = "1" ] && BG_LOG=" BREAK_GLASS=1"

logger -t gateway "shell session start user=${USER} log=${LOG} client=${SSH_CLIENT:-unknown} incident=${PAM_INCIDENT_ID:--}${BG_LOG}"

# Avoid IDE CPR echo on the outer PTY; remote bash still echoes.
stty -echo 2>/dev/null || true

if [ -f /etc/ssh-pam/command_denylist ] || [ -f /run/ssh-pam/command_denylist ]; then
  if [ -f /run/ssh-pam/shell_policy_v2_enabled ] || [ "${PAM_SHELL_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ]; then
    export PAM_DENYLIST=/run/ssh-pam/command_denylist
    [ -f "${PAM_DENYLIST}" ] || export PAM_DENYLIST=/etc/ssh-pam/command_denylist
    export PAM_GATEWAY_MODE=shell
    exec script -q -f -c "/usr/local/bin/pam-pty-inspector.sh /bin/bash --login" "${LOG}"
  fi
  export PAM_DENYLIST=/run/ssh-pam/command_denylist
  [ -f "${PAM_DENYLIST}" ] || export PAM_DENYLIST=/etc/ssh-pam/command_denylist
  exec script -q -f -c "/usr/local/bin/pam-command-policy.sh /bin/bash --login" "${LOG}"
fi
exec script -q -f -c "/bin/bash --login" "${LOG}"
