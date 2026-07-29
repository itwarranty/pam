#!/usr/bin/env bash
# Smoke test: shell command policy v2 (PTY inspector) without interactive TTY.
# Avoids hanging on script(1) when run via podman exec without -t (see QA note below).
#
# Usage (on Rocky gateway host or limactl shell):
#   ./scripts/test-shell-policy-v2.sh
#
# Env: PAM_USER, PAM_CONTAINER_NAME

set -euo pipefail

PAM_USER="${PAM_USER:-gateway}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
DENYLIST="${PAM_DENYLIST:-/run/ssh-pam/command_denylist}"

run_as_pam() {
  local uid rt
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  rt="/run/user/${uid}"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] %s\n' "$*"; }

run_as_pam podman exec "${CONTAINER}" test -f /run/ssh-pam/shell_policy_v2_enabled \
  || fail "shell_policy_v2_enabled marker missing — redeploy with v2 enabled"

run_as_pam podman exec "${CONTAINER}" test -f "${DENYLIST}" \
  || fail "denylist missing at ${DENYLIST}"

# Piped stdin → pty-inspector (no script(1); script without -t hangs forever).
out="$(printf 'rm -rf /\n' | run_as_pam podman exec -i -u engineer-shell "${CONTAINER}" \
  sh -c "timeout 10 env PAM_DENYLIST='${DENYLIST}' PAM_GATEWAY_MODE=shell \
    /usr/local/bin/pam-pty-inspector.sh /bin/bash --login -c 'echo SHOULD_NOT_RUN'" 2>&1 || true)"

printf '%s\n' "${out}" | grep -q 'Command denied' \
  || fail "expected deny message, got: ${out}"

pass "shell policy v2 — denylist blocks destructive command (mode=shell)"
