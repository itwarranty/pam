#!/usr/bin/env bash
# Verify documented pam CLI entry points exist (Runbooks + README).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAM="${ROOT}/scripts/pam"
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    printf '[PASS] runbook-cmd: %s\n' "${label}"
  else
    printf '[FAIL] runbook-cmd: %s\n' "${label}" >&2
    failures=$((failures + 1))
  fi
}

[[ -x "${PAM}" ]] || { printf '[FAIL] missing %s\n' "${PAM}" >&2; exit 1; }

check "pam help" "${PAM}" help
check "pam doctor --help" bash "${ROOT}/scripts/pam-doctor.sh" --help
check "pam verify script" test -x "${ROOT}/scripts/pam-compliance-verify.sh"
check "pam sessions list script" test -x "${ROOT}/scripts/pam-session-ctl.sh"
check "pam sessions search" bash "${ROOT}/scripts/pam-session-search.sh" --help
check "pam sessions watch script" test -x "${ROOT}/scripts/pam-session-watch.sh"
check "pam up script" test -x "${ROOT}/scripts/quickstart.sh"
check "ansible site.yml" ansible-playbook --syntax-check "${ROOT}/site.yml"

if [[ "${failures}" -gt 0 ]]; then
  printf '[FAIL] runbook command check: %s failure(s)\n' "${failures}" >&2
  exit 1
fi
printf '[PASS] runbook command check: all documented entry points OK\n'
