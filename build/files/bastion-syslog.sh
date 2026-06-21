#!/bin/sh
# Gateway audit syslog: append-only file on shared volume + host journal when /dev/log exists.
set -eu

tag="${1:?tag}"
shift
msg="$*"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
logfile="${BASTION_SYSLOG_FILE:-/var/log/bastion_sessions/bastion.syslog}"

printf '%s %s: %s\n' "${ts}" "${tag}" "${msg}" >> "${logfile}" 2>/dev/null || true

if [ -e /dev/log ]; then
  logger -t "${tag}" "${msg}" 2>/dev/null || true
fi
