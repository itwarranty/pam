#!/usr/bin/env bash
# MFA secret must survive unchanged ansible deploy (lab operator with fixed secret).
set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
OPERATOR="${PAM_TEST_OPERATOR:-engineer-jump}"
SECRET_PATH="/home/${PAM_USER}/operators/${OPERATOR}/.google_authenticator"

fail() { printf '[FAIL] mfa-preserve: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] mfa-preserve: %s\n' "$*"; }

[[ -f "${SECRET_PATH}" ]] || fail "missing ${SECRET_PATH} — deploy lab first (runs on gateway host, not inside container)"

before="$(sudo head -1 "${SECRET_PATH}" | tr -d '[:space:]')"
[[ -n "${before}" ]] || fail "empty secret before deploy"

if [[ "${RUN_ANSIBLE:-0}" == "1" ]]; then
  ansible-playbook -i inventory/local-lima.yml site.yml "$@" >/dev/null
fi

after="$(sudo head -1 "${SECRET_PATH}" | tr -d '[:space:]')"
[[ "${before}" == "${after}" ]] || fail "secret changed: before=${before} after=${after}"

pass "operator ${OPERATOR} TOTP secret unchanged"
