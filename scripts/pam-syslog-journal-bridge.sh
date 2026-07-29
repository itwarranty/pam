#!/usr/bin/env bash
# Relay new lines from gateway.syslog (container) into host journald for journalctl -t queries.
set -euo pipefail

LOG="${PAM_SYSLOG_FILE:-/var/log/pam_sessions/gateway.syslog}"
STATE="${PAM_SYSLOG_JOURNAL_STATE:-/var/lib/gateway/syslog-journal.offset}"

mkdir -p "$(dirname "${STATE}")"
touch "${LOG}" 2>/dev/null || true
offset="$(cat "${STATE}" 2>/dev/null || echo 0)"
size="$(stat -c '%s' "${LOG}" 2>/dev/null || echo 0)"

if [[ "${size}" -lt "${offset}" ]]; then
  offset=0
fi

tail -c +"$((offset + 1))" "${LOG}" 2>/dev/null | while IFS= read -r line; do
  [[ -n "${line}" ]] || continue
  tag="$(printf '%s' "${line}" | awk '{print $2}' | tr -d ':')"
  msg="$(printf '%s' "${line}" | cut -d' ' -f3-)"
  [[ -n "${tag}" && -n "${msg}" ]] || continue
  logger -t "${tag}" "${msg}" 2>/dev/null || true
done

printf '%s' "${size}" > "${STATE}"
