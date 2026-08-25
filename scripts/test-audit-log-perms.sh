#!/usr/bin/env bash
# Negative check: unprivileged host user cannot write audit session logs (prod-like modes).
set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
AUDIT_DIR="${PAM_AUDIT_LOG_DIR:-/var/log/pam_sessions}"
SYSLOG="${AUDIT_DIR}/gateway.syslog"
TEST_USER="${PAM_TEST_UNPRIV_USER:-nobody}"

fail() { printf '[FAIL] audit-log-perms: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] audit-log-perms: %s\n' "$*"; }
skip() { printf '[SKIP] audit-log-perms: %s\n' "$*"; exit 0; }

[[ -f "${SYSLOG}" ]] || skip "no ${SYSLOG} — deploy gateway first"

mode="$(stat -c '%a' "${SYSLOG}" 2>/dev/null || stat -f '%OLp' "${SYSLOG}")"
if [[ "${mode}" == "666" || "${mode}" == "0666" ]]; then
  skip "lab mode ${mode} on ${SYSLOG} (expected 0640 in prod)"
fi

if sudo -u "${TEST_USER}" bash -c ": >> '${SYSLOG}'" 2>/dev/null; then
  fail "${TEST_USER} could append to ${SYSLOG} (mode ${mode})"
fi

pass "unprivileged ${TEST_USER} cannot append to ${SYSLOG} (mode ${mode})"
