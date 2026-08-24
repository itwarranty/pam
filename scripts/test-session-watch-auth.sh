#!/usr/bin/env bash
# Live watch authorization: unprivileged caller must be rejected.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAM_USER="${PAM_USER:-pam}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
MOD_GROUP="${PAM_MODERATORS_GROUP:-pam-moderators}"

run_as_pam() {
  local uid rt
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  rt="/run/user/${uid}"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

fail() { printf '[FAIL] session-watch-auth: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] session-watch-auth: %s\n' "$*"; }

SID="watch-auth-$$"
REG="/run/ssh-pam/sessions/${SID}.json"
LOG="/var/log/pam_sessions/watch_auth_test.log"

run_as_pam podman exec "${CONTAINER}" sh -c "
  mkdir -p /run/ssh-pam/sessions
  touch '${LOG}'
  printf '{\"schema\":2,\"id\":\"${SID}\",\"operator\":\"gateway-lab\",\"target_id\":\"lab\",\"log_path\":\"${LOG}\"}\n' > '${REG}'
"

rc=0
sudo runuser -u "${PAM_USER}" -- env \
  PAM_CONTAINER_NAME="${CONTAINER}" \
  PAM_MODERATORS_GROUP="${MOD_GROUP}" \
  PAM_HOME="/home/${PAM_USER}" \
  "${ROOT}/scripts/pam-session-watch.sh" "${SID}" >/dev/null 2>&1 || rc=$?

run_as_pam podman exec "${CONTAINER}" rm -f "${REG}" "${LOG}" 2>/dev/null || true

[[ "${rc}" -ne 0 ]] || fail "unprivileged pam user was allowed to watch"
pass "unauthorized watch rejected for pam user"
