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

if [[ "${SKIP_MFA_ROTATE:-1}" != "1" ]]; then
  run_one "${ROOT}/scripts/test-mfa-rotate.sh"
else
  printf '\n== test-mfa-rotate.sh (skipped — set SKIP_MFA_ROTATE=0 to run) ==\n'
fi

if [[ "${SKIP_AUDIT_LOG_PERMS:-0}" != "1" ]]; then
  run_one "${ROOT}/scripts/test-audit-log-perms.sh"
else
  printf '\n== test-audit-log-perms.sh (skipped) ==\n'
fi

if [[ "${SKIP_PROD_AUDIT:-0}" != "1" ]]; then
  run_one "${ROOT}/scripts/test-prod-audit-modes.sh"
else
  printf '\n== test-prod-audit-modes.sh (skipped — set SKIP_PROD_AUDIT=0 on gateway) ==\n'
fi

if [[ "${SKIP_DEPLOY_BLOCK:-0}" != "1" ]]; then
  run_one "${ROOT}/scripts/test-deploy-active-session-block.sh"
else
  printf '\n== test-deploy-active-session-block.sh (skipped) ==\n'
fi

if [[ "${SKIP_VERIFY_JSON:-0}" != "1" ]]; then
  run_one "${ROOT}/scripts/test-pam-verify-json.sh"
else
  printf '\n== test-pam-verify-json.sh (skipped) ==\n'
fi

printf '\n'
if [[ "${failures}" -gt 0 ]]; then
  printf '[FAIL] security hardening acceptance: %s check(s) failed\n' "${failures}" >&2
  exit 1
fi
printf '[PASS] security hardening acceptance: all checks OK\n'
