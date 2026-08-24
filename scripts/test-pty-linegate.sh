#!/usr/bin/env bash
# Verify PTY line-gate: denied logical line must not reach child stdin consumer.
set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
DENYLIST="${PAM_DENYLIST:-/run/ssh-pam/command_denylist}"

run_as_pam() {
  local uid rt
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  rt="/run/user/${uid}"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

fail() { printf '[FAIL] pty-linegate: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] pty-linegate: %s\n' "$*"; }

run_as_pam podman exec "${CONTAINER}" test -f "${DENYLIST}" \
  || fail "denylist missing at ${DENYLIST}"

# Child `wc -c` counts bytes received on stdin. Denied line must not be forwarded.
out="$(printf 'rm -rf /\n' | run_as_pam podman exec -i "${CONTAINER}" \
  sh -c "timeout 8 env PAM_DENYLIST='${DENYLIST}' PAM_GATEWAY_MODE=gateway \
    /usr/local/bin/pam-pty-inspector.py wc -c" 2>&1 || true)"

printf '%s\n' "${out}" | grep -q 'Command denied' \
  || fail "expected deny banner, got: ${out}"

byte_count="$(printf '%s\n' "${out}" | awk '/^[0-9]+$/{n=$1} END{print n+0}')"
[[ "${byte_count}" -eq 0 ]] || fail "child received ${byte_count} bytes, expected 0"

pass "denied line not forwarded to child PTY"
