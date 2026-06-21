#!/usr/bin/env bash
# Live tail of active gateway session log (four-eyes moderation).
set -euo pipefail

SESSIONS_DIR="${BASTION_RUNTIME_SESSIONS_DIR:-/home/bastion/runtime/sessions}"
JSONL="${AUDIT_LOG_DIR:-/var/log/bastion_sessions}/sessions.jsonl"
CONTAINER="${BASTION_CONTAINER_NAME:-ssh_bastion}"
MODERATOR="${SUDO_USER:-${USER:-unknown}}"

usage() {
  echo "Usage: bastion-session-watch <session-id>"
  echo "       bastion-session-watch --list  (alias: bastion-session-ctl list)"
}

append_jsonl() {
  local line="$1"
  [[ -f "${JSONL}" ]] || touch "${JSONL}" 2>/dev/null || true
  printf '%s\n' "${line}" >> "${JSONL}" 2>/dev/null || true
}

if [[ "${1:-}" == "--list" ]]; then
  exec bastion-session-ctl list
fi

SID="${1:-}"
[[ -n "${SID}" ]] || { usage; exit 1; }

REG="${SESSIONS_DIR}/${SID}.json"
if [[ ! -f "${REG}" ]] && command -v podman >/dev/null 2>&1; then
  REG_CONTENT="$(podman exec "${CONTAINER}" cat "/run/bastion/sessions/${SID}.json" 2>/dev/null || true)"
else
  REG_CONTENT="$(cat "${REG}" 2>/dev/null || true)"
fi

[[ -n "${REG_CONTENT}" ]] || { echo "Session not found: ${SID}" >&2; exit 1; }

LOG_PATH="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"log_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
OPERATOR="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"operator"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
TARGET_ID="$(printf '%s' "${REG_CONTENT}" | sed -n 's/.*"target_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

logger -t bastion-moderator "watch start session=${SID} moderator=${MODERATOR} operator=${OPERATOR}"
append_jsonl "$(printf '{"event":"moderator_watch_start","ts":"%s","session_id":"%s","operator":"%s","target_id":"%s","moderator":"%s"}' \
  "${UTC}" "${SID}" "${OPERATOR}" "${TARGET_ID}" "${MODERATOR}")"

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
