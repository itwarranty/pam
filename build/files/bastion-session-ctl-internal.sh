#!/bin/sh
# In-container session control (list/kill). Host wrapper: scripts/bastion-session-ctl.sh
set -eu

SESSIONS_DIR="${BASTION_SESSIONS_DIR:-/run/bastion/sessions}"
TIMEOUT="${BASTION_KILL_TIMEOUT:-10}"

_usage() {
  cat <<'EOF'
Usage: bastion-session-ctl-internal list
       bastion-session-ctl-internal kill <session-id>
       bastion-session-ctl-internal kill --operator <name>
EOF
}

_list() {
  if [ ! -d "${SESSIONS_DIR}" ] || [ -z "$(ls -A "${SESSIONS_DIR}" 2>/dev/null)" ]; then
    printf 'No active gateway sessions.\n'
    return 0
  fi
  printf '%-22s %-16s %-16s %-21s %s\n' "SESSION_ID" "OPERATOR" "TARGET" "STARTED" "TARGET_HOST"
  for f in "${SESSIONS_DIR}"/*.json; do
    [ -f "${f}" ] || continue
    awk -F'"' '
      /"id"/ { for (i=1;i<=NF;i++) if ($i=="id") id=$(i+2) }
      /"operator"/ { for (i=1;i<=NF;i++) if ($i=="operator") op=$(i+2) }
      /"target_id"/ { for (i=1;i<=NF;i++) if ($i=="target_id") tid=$(i+2) }
      /"target_host"/ { for (i=1;i<=NF;i++) if ($i=="target_host") th=$(i+2) }
      /"started_at"/ { for (i=1;i<=NF;i++) if ($i=="started_at") st=$(i+2) }
      END { if (id) printf "%-22s %-16s %-16s %-21s %s\n", id, op, tid, st, th }
    ' "${f}"
  done
}

_kill_one() {
  sid="$1"
  reg="${SESSIONS_DIR}/${sid}.json"
  [ -f "${reg}" ] || { printf 'Session not found: %s\n' "${sid}" >&2; return 1; }
  pid="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "${reg}" | head -1)"
  op="$(awk -F'"' '/"operator"/ { for (i=1;i<=NF;i++) if ($i=="operator") { print $(i+2); exit } }' "${reg}")"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}" 2>/dev/null || true
    i=0
    while [ "${i}" -lt "${TIMEOUT}" ]; do
      kill -0 "${pid}" 2>/dev/null || break
      sleep 1
      i=$((i + 1))
    done
    kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}" 2>/dev/null || true
  fi
  rm -f "${reg}" 2>/dev/null || true
  /usr/local/bin/bastion-syslog.sh bastion-session-kill "session=${sid} operator=${op:-unknown} pid=${pid:-unknown}"
  printf 'Killed session %s (operator=%s)\n' "${sid}" "${op:-unknown}"
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
