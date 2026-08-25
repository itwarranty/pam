#!/usr/bin/env bash
# MFA rotation: only operators in pam_mfa_rotate_operators change; others preserved.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAM_USER="${PAM_USER:-pam}"
ROTATE="${PAM_MFA_ROTATE_OPERATOR:-engineer-jump}"
KEEP="${PAM_MFA_KEEP_OPERATOR:-engineer-shell}"
ROTATE_PATH="/home/${PAM_USER}/operators/${ROTATE}/.google_authenticator"
KEEP_PATH="/home/${PAM_USER}/operators/${KEEP}/.google_authenticator"

fail() { printf '[FAIL] mfa-rotate: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] mfa-rotate: %s\n' "$*"; }

[[ -f "${ROTATE_PATH}" ]] || fail "missing ${ROTATE_PATH}"
[[ -f "${KEEP_PATH}" ]] || fail "missing ${KEEP_PATH}"

before_rotate="$(sudo head -1 "${ROTATE_PATH}" | tr -d '[:space:]')"
before_keep="$(sudo head -1 "${KEEP_PATH}" | tr -d '[:space:]')"
[[ -n "${before_rotate}" && -n "${before_keep}" ]] || fail "empty secret(s) before rotate"

if [[ "${RUN_ANSIBLE:-1}" == "1" ]]; then
  ansible-playbook -i inventory/local-lima.yml site.yml \
    -e "{\"pam_mfa_rotate_operators\": [\"${ROTATE}\"]}" "$@" >/dev/null
fi

after_rotate="$(sudo head -1 "${ROTATE_PATH}" | tr -d '[:space:]')"
after_keep="$(sudo head -1 "${KEEP_PATH}" | tr -d '[:space:]')"

[[ "${before_rotate}" != "${after_rotate}" ]] || fail "${ROTATE} secret unchanged after rotate"
[[ "${before_keep}" == "${after_keep}" ]] || fail "${KEEP} secret changed unexpectedly"

pass "rotated ${ROTATE}; ${KEEP} unchanged"
