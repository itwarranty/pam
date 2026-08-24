#!/bin/sh
# In-container session control (list/kill). Host wrapper: scripts/pam-session-ctl.sh
set -eu

SESSIONS_DIR="${PAM_SESSIONS_DIR:-/run/ssh-pam/sessions}"
TIMEOUT="${PAM_KILL_TIMEOUT:-10}"
KILL_SIGKILL="${PAM_KILL_USE_SIGKILL:-1}"
PAM_RUNTIME_USER="${PAM_RUNTIME_USER:-pam}"

_usage() {
  cat <<'EOF'
Usage: pam-session-ctl-internal list
       pam-session-ctl-internal kill <session-id>
       pam-session-ctl-internal kill --operator <name>
EOF
}

_validate_registry() {
  reg="$1"
  [ -f "${reg}" ] || return 1
  owner="$(stat -c '%U' "${reg}" 2>/dev/null || echo unknown)"
  [ "${owner}" = "${PAM_RUNTIME_USER}" ] || {
    printf 'Registry ownership invalid: %s (owner=%s)\n' "${reg}" "${owner}" >&2
    return 1
  }
  return 0
}

_read_field() {
  reg="$1"
  field="$2"
  sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "${reg}" | head -1
}

_read_numeric_field() {
  reg="$1"
  field="$2"
  sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" "${reg}" | head -1
}

_pgid_alive() {
  pgid="$1"
  [ -n "${pgid}" ] || return 1
  ps -o pgid= -p "${pgid}" >/dev/null 2>&1 && return 0
  kill -0 "-${pgid}" 2>/dev/null
}

_kill_pgid() {
  pgid="$1"
  sid="$2"
  op="$3"
  [ -n "${pgid}" ] || return 0
  /usr/local/bin/pam-syslog.sh pam-session-kill \
    "event=session_kill_start session=${sid} operator=${op:-unknown} pgid=${pgid}"
  if _pgid_alive "${pgid}"; then
    kill -TERM "-${pgid}" 2>/dev/null || true
    i=0
    while [ "${i}" -lt "${TIMEOUT}" ]; do
      _pgid_alive "${pgid}" || break
      sleep 1
      i=$((i + 1))
    done
    if _pgid_alive "${pgid}" && [ "${KILL_SIGKILL}" = "1" ]; then
      kill -KILL "-${pgid}" 2>/dev/null || true
    fi
  fi
  result="ok"
  _pgid_alive "${pgid}" && result="partial"
  /usr/local/bin/pam-syslog.sh pam-session-kill \
    "event=session_kill_end session=${sid} operator=${op:-unknown} pgid=${pgid} result=${result}"
}

_list() {
  if [ ! -d "${SESSIONS_DIR}" ] || [ -z "$(ls -A "${SESSIONS_DIR}" 2>/dev/null)" ]; then
    printf 'No active gateway sessions.\n'
    return 0
  fi
  printf '%-22s %-16s %-16s %-8s %-8s %-21s %s\n' \
    "SESSION_ID" "OPERATOR" "TARGET" "PID" "PGID" "STARTED" "TARGET_HOST"
  for f in "${SESSIONS_DIR}"/*.json; do
    [ -f "${f}" ] || continue
    awk -F'"' '
      /"id"/ { for (i=1;i<=NF;i++) if ($i=="id") id=$(i+2) }
      /"operator"/ { for (i=1;i<=NF;i++) if ($i=="operator") op=$(i+2) }
      /"target_id"/ { for (i=1;i<=NF;i++) if ($i=="target_id") tid=$(i+2) }
      /"target_host"/ { for (i=1;i<=NF;i++) if ($i=="target_host") th=$(i+2) }
      /"started_at"/ { for (i=1;i<=NF;i++) if ($i=="started_at") st=$(i+2) }
      /"pid"/ { for (i=1;i<=NF;i++) if ($i=="pid") pid=$(i+2) }
      /"pgid"/ { for (i=1;i<=NF;i++) if ($i=="pgid") pgid=$(i+2) }
      END {
        if (id) printf "%-22s %-16s %-16s %-8s %-8s %-21s %s\n", id, op, tid, pid, pgid, st, th
      }
    ' "${f}"
  done
}

_kill_one() {
  sid="$1"
  case "${sid}" in
    *..*|*/*|\\*) printf 'Invalid session id: %s\n' "${sid}" >&2; return 1 ;;
  esac
  reg="${SESSIONS_DIR}/${sid}.json"
  _validate_registry "${reg}" || { printf 'Session not found: %s\n' "${sid}" >&2; return 1; }

  schema="$(_read_numeric_field "${reg}" schema)"
  pid="$(_read_numeric_field "${reg}" pid)"
  pgid="$(_read_numeric_field "${reg}" pgid)"
  op="$(_read_field "${reg}" operator)"

  if [ -z "${pgid}" ] && [ -n "${pid}" ]; then
    pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ')"
    [ -n "${schema}" ] || {
      printf 'Warning: legacy session registry (schema v1); using pid-derived pgid.\n' >&2
    }
  fi

  proc_user=""
  if [ -n "${pid}" ]; then
    proc_user="$(ps -o user= -p "${pid}" 2>/dev/null | tr -d ' ')"
    if [ -n "${proc_user}" ] && [ "${proc_user}" != "${PAM_RUNTIME_USER}" ]; then
      printf 'Session pid owner mismatch: %s\n' "${proc_user}" >&2
      return 1
    fi
  fi

  _kill_pgid "${pgid}" "${sid}" "${op}"
  rm -f "${reg}" 2>/dev/null || true
  printf 'Killed session %s (operator=%s pgid=%s)\n' "${sid}" "${op:-unknown}" "${pgid:-unknown}"
}

_kill() {
  if [ "${1:-}" = "--operator" ]; then
    op="${2:?operator name}"
    found=0
    for f in "${SESSIONS_DIR}"/*.json; do
      [ -f "${f}" ] || continue
      if grep -q "\"operator\"[[:space:]]*:[[:space:]]*\"${op}\"" "${f}"; then
        sid="$(basename "${f}" .json)"
        _kill_one "${sid}" && found=1
      fi
    done
    [ "${found}" -eq 1 ] || { printf 'No active sessions for operator: %s\n' "${op}" >&2; return 1; }
    return 0
  fi
  _kill_one "${1:?session id}"
}

cmd="${1:-}"
case "${cmd}" in
  list) _list ;;
  kill) shift; _kill "$@" ;;
  *) _usage; exit 1 ;;
esac
