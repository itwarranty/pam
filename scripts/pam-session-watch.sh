#!/usr/bin/env bash
# Live tail of active gateway session log (four-eyes moderation).
set -euo pipefail

PAM_HOME="${PAM_HOME:-/home/pam}"
SESSIONS_DIR="${PAM_RUNTIME_SESSIONS_DIR:-${PAM_HOME}/runtime/sessions}"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/pam_sessions}"
JSONL="${AUDIT_LOG_DIR}/sessions.jsonl"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
MODERATORS_GROUP="${PAM_MODERATORS_GROUP:-pam-moderators}"
MODERATOR="${SUDO_USER:-${USER:-unknown}}"

usage() {
  echo "Usage: pam-session-watch <session-id>"
  echo "       pam-session-watch --list  (alias: pam-session-ctl list)"
}

append_jsonl() {
  local line="$1"
  [[ -f "${JSONL}" ]] || touch "${JSONL}" 2>/dev/null || true
  printf '%s\n' "${line}" >> "${JSONL}" 2>/dev/null || true
}

audit_event() {
  local outcome="$1"
  local detail="$2"
  logger -t gateway-moderator "${detail}" 2>/dev/null || true
  append_jsonl "$(printf \
    '{"event":"moderator_watch_%s","ts":"%s","session_id":"%s","moderator":"%s","detail":"%s"}' \
    "${outcome}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${SID:-unknown}" "${MODERATOR}" "${detail}")"
}

authorized_watch() {
  if [[ "$(id -u)" -eq 0 ]]; then
    return 0
  fi
  if id -nG "${USER}" 2>/dev/null | tr ' ' '\n' | grep -qx "${MODERATORS_GROUP}"; then
    return 0
  fi
  return 1
}

canonical_log_path() {
  local raw="$1"
  local canonical audit_root
  canonical="$(realpath -m "${raw}" 2>/dev/null || return 1)"
  audit_root="$(realpath -m "${AUDIT_LOG_DIR}" 2>/dev/null || return 1)"
  case "${canonical}" in
    "${audit_root}"|"${audit_root}"/*)
      if [[ -L "${canonical}" ]]; then
        return 1
      fi
      printf '%s' "${canonical}"
      return 0
      ;;
  esac
  return 1
}

if [[ "${1:-}" == "--list" ]]; then
  exec pam-session-ctl list
fi

SID="${1:-}"
[[ -n "${SID}" ]] || { usage; exit 1; }
case "${SID}" in
  *..*|*/*|\\*) echo "Invalid session id: ${SID}" >&2; exit 1 ;;
esac

if ! authorized_watch; then
  audit_event "deny" "watch denied session=${SID} moderator=${MODERATOR} reason=unauthorized"
  echo "Unauthorized: live watch requires root or group ${MODERATORS_GROUP}." >&2
  exit 1
fi

REG="${SESSIONS_DIR}/${SID}.json"
if [[ ! -f "${REG}" ]] && command -v podman >/dev/null 2>&1; then
  REG_CONTENT="$(podman exec "${CONTAINER}" cat "/run/ssh-pam/sessions/${SID}.json" 2>/dev/null || true)"
else
  REG_CONTENT="$(cat "${REG}" 2>/dev/null || true)"
fi

[[ -n "${REG_CONTENT}" ]] || {
  audit_event "deny" "watch denied session=${SID} moderator=${MODERATOR} reason=not_found"
  echo "Session not found: ${SID}" >&2
  exit 1
}

LOG_RAW="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"log_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
OPERATOR="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"operator"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
TARGET_ID="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"target_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

LOG_PATH="$(canonical_log_path "${LOG_RAW}" 2>/dev/null || true)"
[[ -n "${LOG_PATH}" ]] || {
  audit_event "deny" "watch denied session=${SID} moderator=${MODERATOR} reason=bad_log_path"
  echo "Log path rejected (must be under ${AUDIT_LOG_DIR}): ${LOG_RAW}" >&2
  exit 1
}

audit_event "allow" "watch start session=${SID} moderator=${MODERATOR} operator=${OPERATOR}"
printf 'Watching session %s (operator=%s) log=%s\n' "${SID}" "${OPERATOR}" "${LOG_PATH}" >&2
printf 'Read-only tail — Ctrl+C to stop.\n\n' >&2

if [[ -f "${LOG_PATH}" ]]; then
  tail -f "${LOG_PATH}"
elif command -v podman >/dev/null 2>&1; then
  podman exec "${CONTAINER}" tail -f "${LOG_PATH}"
else
  echo "Log not accessible: ${LOG_PATH}" >&2
  exit 1
fi
