#!/usr/bin/env bash
# Prod-like audit log modes (0640/0750) and negative append check.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pam-test-lib.sh
source "${ROOT}/scripts/lib/pam-test-lib.sh"
cd "${ROOT}"

PAM_USER="${PAM_USER:-pam}"
AUDIT_DIR="${PAM_AUDIT_LOG_DIR:-/var/log/pam_sessions}"
AUDIT_GROUP="${PAM_AUDIT_GROUP:-pam-audit}"

fail() { printf '[FAIL] prod-audit-modes: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] prod-audit-modes: %s\n' "$*"; }

_apply_modes() {
  local dir_mode="$1" file_mode="$2"
  pam_test_run_gateway "
    set -euo pipefail
    d=${AUDIT_DIR}
    u=${PAM_USER}
    g=${AUDIT_GROUP}
    install -d -m ${dir_mode} -o \"\${u}\" -g \"\${g}\" \"\${d}\"
    touch \"\${d}/gateway.syslog\" \"\${d}/sessions.jsonl\"
    chown \"\${u}:\${g}\" \"\${d}/gateway.syslog\" \"\${d}/sessions.jsonl\"
    chmod ${file_mode} \"\${d}/gateway.syslog\" \"\${d}/sessions.jsonl\"
  "
}

if [[ "${APPLY_VIA_ANSIBLE:-0}" == "1" ]] && ! pam_test_on_gateway; then
  INVENTORY="$(pam_test_inventory)"
  OVERLAY="${ROOT}/group_vars/dev/prod_audit_overlay.yml"
  printf 'Applying prod audit overlay via Ansible (inventory=%s)...\n' "${INVENTORY}"
  ansible-playbook -i "${INVENTORY}" site.yml -e @"${OVERLAY}" >/dev/null \
    || fail "ansible overlay apply failed"
else
  printf 'Applying prod audit modes on gateway host...\n'
  _apply_modes 0750 0640
fi

pam_test_run_gateway "
  export PAM_AUDIT_LOG_DIR_MODE=750 PAM_AUDIT_LOG_FILE_MODE=640
  export PAM_AUDIT_LOG_DIR=${AUDIT_DIR}
  ${ROOT}/scripts/pam-compliance-verify.sh 2>&1 | grep -E 'session_log_dir|gateway_syslog'
  ${ROOT}/scripts/test-audit-log-perms.sh
" || fail "compliance or negative perm check failed"

pass "prod-like audit modes enforced; negative append check OK"

printf 'Restoring lab audit modes...\n'
_apply_modes 1777 0666

pass "lab audit modes restored"
