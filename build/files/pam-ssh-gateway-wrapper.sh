#!/bin/sh
# ForceCommand wrapper for access: gateway — target selection, session registry, recording.
set -eu

_sanitize() {
  printf '%s' "${1}" | tr -cd 'A-Za-z0-9._-' | cut -c1-64
}

SESSIONS_DIR="${PAM_SESSIONS_DIR:-/run/ssh-pam/sessions}"
TARGETS_ROOT="${PAM_TARGETS_DIR:-/run/ssh-pam/targets-runtime}"
[ -d "${TARGETS_ROOT}" ] || TARGETS_ROOT="/etc/ssh-pam/targets"
PERMIT_FILE="/home/${USER}/permit_open"
JSONL="${PAM_JSONL:-/var/log/pam_sessions/sessions.jsonl}"
TARGETS_LIST="/tmp/.pam-gw-targets.$$"

_fail() {
  /usr/local/bin/pam-syslog.sh gateway-gateway "user=${USER} error=$* client=${SSH_CLIENT:-unknown}"
  printf '[SSH PAM Gateway] %s\n' "$*" >&2
  exit 1
}

_append_jsonl() {
  [ -n "${JSONL}" ] || return 0
  printf '%s\n' "$1" >> "${JSONL}" 2>/dev/null || true
}

_resolve_targets() {
  : > "${TARGETS_LIST}"
  for envf in "${TARGETS_ROOT}"/*/target.env; do
    [ -f "${envf}" ] || continue
    # shellcheck disable=SC1090
    . "${envf}"
    hp="${HOST}:${PORT}"
    if grep -qFx "${hp}" "${PERMIT_FILE}" 2>/dev/null; then
      printf '%s\t%s\n' "${ID}" "${hp}" >> "${TARGETS_LIST}"
    fi
  done
}

_select_target() {
  [ -f "${PERMIT_FILE}" ] || _fail "Operator permit_open file missing."
  _resolve_targets
  count="$(wc -l < "${TARGETS_LIST}" | tr -d ' ')"
  [ "${count}" -gt 0 ] || _fail "No permitted targets match pam_targets inventory."

  if [ "${count}" -eq 1 ]; then
    cut -f1 "${TARGETS_LIST}"
    return
  fi

  printf '\n[SSH PAM Gateway] Select target:\n' >&2
  n=1
  while IFS="$(printf '\t')" read -r tid hp; do
    printf '  %s) %s (%s)\n' "${n}" "${tid}" "${hp}" >&2
    n=$((n + 1))
  done < "${TARGETS_LIST}"

  printf 'Enter number: ' >&2
  read -r choice </dev/tty
  sed -n "${choice}p" "${TARGETS_LIST}" | cut -f1
}

SESSION_ID="$(date -u +%Y%m%d-%H%M%S)-$$"
TARGET_ID="$(_select_target)"
rm -f "${TARGETS_LIST}"
[ -n "${TARGET_ID}" ] || _fail "Invalid target selection."

# shellcheck disable=SC1090
. "${TARGETS_ROOT}/${TARGET_ID}/target.env"

INCIDENT_RAW="${PAM_INCIDENT_ID:-}"
INCIDENT_TAG=""
[ -n "${INCIDENT_RAW}" ] && [ "${INCIDENT_RAW}" != "-" ] && INCIDENT_TAG="$(_sanitize "${INCIDENT_RAW}")"

TS="$(date +%Y%m%d_%H%M%S)"
TID_TAG="$(_sanitize "${TARGET_ID}")"
if [ -n "${INCIDENT_TAG}" ]; then
  LOG="/var/log/pam_sessions/gateway_${INCIDENT_TAG}_${USER}_${TID_TAG}_${TS}.log"
else
  LOG="/var/log/pam_sessions/gateway_${USER}_${TID_TAG}_${TS}.log"
fi

mkdir -p "${SESSIONS_DIR}"
REG_FILE="${SESSIONS_DIR}/${SESSION_ID}.json"
UTC_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
CLIENT="${SSH_CLIENT:-unknown}"

printf '{"id":"%s","operator":"%s","target_id":"%s","target_host":"%s","target_port":%s,"target_account":"%s","pid":%s,"started_at":"%s","log_path":"%s"}\n' \
  "${SESSION_ID}" "${USER}" "${TARGET_ID}" "${HOST}" "${PORT}" "${ACCOUNT}" "$$" "${UTC_START}" "${LOG}" \
  > "${REG_FILE}"

/usr/local/bin/pam-syslog.sh gateway-gateway \
  "session start id=${SESSION_ID} user=${USER} target=${TARGET_ID} host=${HOST}:${PORT} log=${LOG} client=${CLIENT}"

_append_jsonl "$(printf \
  '{"event":"gateway_start","ts":"%s","operator":"%s","target_id":"%s","target_host":"%s","target_port":%s,"session_id":"%s","client":"%s","incident_id":"%s"}' \
  "${UTC_START}" "${USER}" "${TARGET_ID}" "${HOST}" "${PORT}" "${SESSION_ID}" "${CLIENT}" "${INCIDENT_RAW:--}")"

touch "${LOG}"
chattr +a "${LOG}" 2>/dev/null || true

export PAM_SESSION_ID="${SESSION_ID}"
export PAM_LOG_PATH="${LOG}"
export PAM_TARGET_ID="${TARGET_ID}"

# Outer PTY echo paints IDE CPR (^[[row;colR]) before the inspector can drop it.
# Remote target ssh -tt still echoes keystrokes.
stty -echo 2>/dev/null || true

/usr/local/bin/pam-ssh-gateway.sh "${TARGET_ID}" "${SESSION_ID}" "${LOG}"
EXIT_CODE=$?

UTC_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_SHA=""
[ -f "${LOG}" ] && LOG_SHA="$(sha256sum "${LOG}" | awk '{print $1}')"

if [ -f "${LOG}" ]; then
  sha256sum "${LOG}" > "${LOG}.sha256"
  printf 'SHA256=%s  UTC=%s  USER=%s  INCIDENT=%s  CLIENT=%s  TARGET=%s  TARGET_HOST=%s  TARGET_ACCOUNT=%s  MODE=gateway\n' \
    "${LOG_SHA}" "${UTC_END}" "${USER}" "${INCIDENT_RAW:--}" "${CLIENT}" \
    "${TARGET_ID}" "${HOST}" "${ACCOUNT}" > "${LOG}.meta"
  chattr +a "${LOG}.sha256" 2>/dev/null || true
  chattr +a "${LOG}.meta" 2>/dev/null || true
fi

_append_jsonl "$(printf \
  '{"event":"gateway_end","ts":"%s","session_id":"%s","operator":"%s","target_id":"%s","exit_code":%s,"log_sha256":"%s"}' \
  "${UTC_END}" "${SESSION_ID}" "${USER}" "${TARGET_ID}" "${EXIT_CODE}" "${LOG_SHA}")"

rm -f "${REG_FILE}" 2>/dev/null || true
/usr/local/bin/pam-syslog.sh gateway-gateway "session end id=${SESSION_ID} user=${USER} exit=${EXIT_CODE}"
exit "${EXIT_CODE}"
