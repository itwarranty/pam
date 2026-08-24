#!/usr/bin/env bash
# Acceptance bundle for OpenSpec 2026-08 security hardening (run on Rocky gateway / Lima).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

failures=0
run_one() {
  local script="$1"
  printf '\n== %s ==\n' "${script}"
  if bash "${script}"; then
    return 0
  fi
  failures=$((failures + 1))
  return 0
}

run_one "${ROOT}/scripts/test-audit-exec-container.sh"
run_one "${ROOT}/scripts/test-shell-policy-v2.sh"
run_one "${ROOT}/scripts/test-pty-linegate.sh"
run_one "${ROOT}/scripts/test-session-pgid-kill.sh"
run_one "${ROOT}/scripts/test-session-watch-auth.sh"

if [[ "${SKIP_MFA_PRESERVE:-0}" != "1" ]]; then
  if [[ -f "/home/${PAM_USER:-pam}/operators/${PAM_TEST_OPERATOR:-engineer-jump}/.google_authenticator" ]]; then
    run_one "${ROOT}/scripts/test-mfa-preserve.sh"
  else
    printf '\n== test-mfa-preserve.sh (skipped — run on gateway host) ==\n'
  fi
else
  printf '\n== test-mfa-preserve.sh (skipped) ==\n'
fi

printf '\n'
if [[ "${failures}" -gt 0 ]]; then
  printf '[FAIL] security hardening acceptance: %s check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf '[PASS] security hardening acceptance: all checks OK\n'
