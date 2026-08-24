#!/usr/bin/env bash
# Process-group kill via pam-session-ctl-internal (schema v2 registry).
set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"

run_as_pam() {
  local uid rt
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  rt="/run/user/${uid}"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

fail() { printf '[FAIL] session-pgid-kill: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] session-pgid-kill: %s\n' "$*"; }

SID="acceptance-kill-$$"
REG="/run/ssh-pam/sessions/${SID}.json"

info="$(run_as_pam podman exec "${CONTAINER}" sh -c "
  set -eu
  setsid sh -c 'sleep 600' &
  pid=\$!
  sleep 0.2
  pgid=\$(awk '{print \$5}' /proc/\${pid}/stat)
  mkdir -p /run/ssh-pam/sessions
  printf '{\"schema\":2,\"id\":\"${SID}\",\"operator\":\"acceptance\",\"pid\":%s,\"pgid\":%s,\"log_path\":\"/var/log/pam_sessions/acceptance.log\"}\n' \"\${pid}\" \"\${pgid}\" > '${REG}'
  printf '%s %s' \"\${pid}\" \"\${pgid}\"
")"

PID="${info%% *}"
PGID="${info##* }"
[[ -n "${PID}" && -n "${PGID}" ]] || fail "failed to start test session"

run_as_pam podman exec "${CONTAINER}" /usr/local/bin/pam-session-ctl-internal kill "${SID}" \
  || fail "kill command failed"

if run_as_pam podman exec "${CONTAINER}" kill -0 "${PID}" 2>/dev/null; then
  fail "wrapper pid still alive after kill"
fi

if run_as_pam podman exec "${CONTAINER}" kill -0 "-${PGID}" 2>/dev/null; then
  fail "process group still alive after kill"
fi

run_as_pam podman exec "${CONTAINER}" test ! -f "${REG}" \
  || fail "registry file not removed"

pass "process group ${PGID} terminated"
