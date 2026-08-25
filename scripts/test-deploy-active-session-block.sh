#!/usr/bin/env bash
# Deploy guard: live session probe + optional full playbook block (slow).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pam-test-lib.sh
source "${ROOT}/scripts/lib/pam-test-lib.sh"
cd "${ROOT}"

PAM_USER="${PAM_USER:-pam}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"

fail() { printf '[FAIL] deploy-session-block: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] deploy-session-block: %s\n' "$*"; }

SID="acceptance-block-$$"
cleanup() {
  pam_test_run_gateway "
    set -euo pipefail
    uid=\$(getent passwd ${PAM_USER} | cut -d: -f3)
    rt=/run/user/\${uid}
    sudo runuser -u ${PAM_USER} -- env XDG_RUNTIME_DIR=\${rt} \
      podman exec ${CONTAINER} sh -c '
        pgid=\$(sed -n \"s/.*\\\"pgid\\\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p\" /run/ssh-pam/sessions/${SID}.json 2>/dev/null | head -1)
        [ -n \"\${pgid}\" ] && kill -TERM \"-\${pgid}\" 2>/dev/null || true
        rm -f /run/ssh-pam/sessions/${SID}.json
      ' 2>/dev/null || true
  " || true
}
trap cleanup EXIT

pam_test_run_gateway "
  set -euo pipefail
  uid=\$(getent passwd ${PAM_USER} | cut -d: -f3)
  rt=/run/user/\${uid}
  sudo runuser -u ${PAM_USER} -- env XDG_RUNTIME_DIR=\${rt} podman exec ${CONTAINER} sh -c '
    set -eu
    setsid sh -c \"sleep 600\" &
    pid=\$!
    sleep 0.2
    pgid=\$(awk \"{print \\\$5}\" /proc/\${pid}/stat)
    mkdir -p /run/ssh-pam/sessions
    printf \"{\\\"schema\\\":2,\\\"id\\\":\\\"${SID}\\\",\\\"operator\\\":\\\"acceptance\\\",\\\"pid\\\":%s,\\\"pgid\\\":%s}\\n\" \"\${pid}\" \"\${pgid}\" > /run/ssh-pam/sessions/${SID}.json
    kill -0 \"-\${pgid}\"
  '
" || fail "could not seed live session"

probe="$(pam_test_run_gateway "
  set -euo pipefail
  uid=\$(getent passwd ${PAM_USER} | cut -d: -f3)
  rt=/run/user/\${uid}
  sudo runuser -u ${PAM_USER} -- env XDG_RUNTIME_DIR=\${rt} \
    podman exec ${CONTAINER} sh -c '
      set -eu
      live=0
      for f in /run/ssh-pam/sessions/*.json; do
        [ -f \"\$f\" ] || continue
        pgid=\$(sed -n \"s/.*\\\"pgid\\\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p\" \"\$f\" | head -1)
        [ -n \"\${pgid}\" ] && kill -0 \"-\${pgid}\" 2>/dev/null && live=\$((live + 1))
      done
      printf \"%s\" \"\${live}\"
    '
")"

[[ "${probe}" -ge 1 ]] || fail "session probe count=${probe} (expected >=1)"
pass "live session probe count=${probe}"

if [[ "${PAM_DEPLOY_BLOCK_FULL:-0}" == "1" ]]; then
  log="$(mktemp)"
  if ansible-playbook -i inventory/local-lima.yml site.yml \
    --start-at-task="[CSO] Проверка активных сессий перед disruptive deploy" >"${log}" 2>&1; then
    tail -20 "${log}" >&2
    fail "playbook succeeded while live session active"
  fi
  grep -q 'Active gateway sessions detected' "${log}" \
    || fail "expected active-session block message in playbook output"
  rm -f "${log}"
  pass "full playbook block confirmed (PAM_DEPLOY_BLOCK_FULL=1)"
fi

cleanup
trap - EXIT
pass "active-session deploy guard OK"
