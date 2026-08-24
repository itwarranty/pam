#!/usr/bin/env bash
# Audit executor injection corpus inside container (no side effects).
set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"

run_as_pam() {
  local uid rt
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  rt="/run/user/${uid}"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

fail() { printf '[FAIL] audit-exec: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] audit-exec: %s\n' "$*"; }

run_as_pam podman exec "${CONTAINER}" test -x /usr/local/bin/pam-audit-exec.py \
  || fail "pam-audit-exec.py missing"

if run_as_pam podman exec "${CONTAINER}" grep -q 'eval ' /usr/local/bin/pam-audit-shell.sh 2>/dev/null; then
  fail "pam-audit-shell.sh still contains eval"
fi

tmpdir="$(run_as_pam podman exec "${CONTAINER}" mktemp -d /tmp/pam-audit-test.XXXXXX)"
trap 'run_as_pam podman exec "${CONTAINER}" rm -rf "${tmpdir}" 2>/dev/null || true' EXIT
run_as_pam podman exec "${CONTAINER}" sh -c "echo sample > '${tmpdir}/sample.log'"

corpus=(
  '\$(id)'
  '\`id\`'
  'cat ${HOME}/x'
  'cat a; id'
  'cat a | wc'
  'cat a > /tmp/x'
)

for line in "${corpus[@]}"; do
  rc=0
  run_as_pam podman exec -e "PAM_AUDIT_LOG_DIR=${tmpdir}" "${CONTAINER}" \
    /usr/local/bin/pam-audit-exec.py --exec "${line}" >/dev/null 2>&1 || rc=$?
  [[ "${rc}" -ne 0 ]] || fail "injection accepted: ${line}"
done

safe_rc=0
run_as_pam podman exec -e "PAM_AUDIT_LOG_DIR=${tmpdir}" "${CONTAINER}" \
  /usr/local/bin/pam-audit-exec.py --exec "cat ${tmpdir}/sample.log" >/dev/null 2>&1 || safe_rc=$?
[[ "${safe_rc}" -eq 0 ]] || fail "safe cat command rejected"

pass "injection corpus denied; safe read allowed"
