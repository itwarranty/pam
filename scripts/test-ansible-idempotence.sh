#!/usr/bin/env bash
# Two-pass Ansible idempotence: second site.yml must not restart the PAM container.
#
# Usage (Rocky gateway / Lima):
#   ./scripts/test-ansible-idempotence.sh
#   ./scripts/test-ansible-idempotence.sh inventory/local-lima.yml
#
# Env:
#   PAM_CONTAINER_NAME  (default: ssh_pam)
#   PAM_USER            (default: pam)
#   LIMA_INSTANCE       (default: pam-prod) — when inventory is local-lima.yml
#   SKIP_MFA_CHECK=1    skip MFA preserve assertion

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

INVENTORY="${1:-inventory/local-lima.yml}"
CONTAINER="${PAM_CONTAINER_NAME:-ssh_pam}"
PAM_USER="${PAM_USER:-pam}"
LIMA_INSTANCE="${LIMA_INSTANCE:-pam-prod}"

fail() { printf '[FAIL] ansible-idempotence: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] ansible-idempotence: %s\n' "$*"; }

_use_lima=0
[[ "${INVENTORY}" == *local-lima* ]] && _use_lima=1

_container_started_at() {
  if [[ "${_use_lima}" -eq 1 ]]; then
    limactl shell "${LIMA_INSTANCE}" -- bash -lc "
      set -euo pipefail
      uid=\$(getent passwd ${PAM_USER} | cut -d: -f3)
      rt=/run/user/\${uid}
      sudo runuser -u ${PAM_USER} -- env XDG_RUNTIME_DIR=\${rt} \
        podman inspect -f '{{.State.StartedAt}}' ${CONTAINER}
    "
  else
    local uid rt
    uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
    rt="/run/user/${uid}"
    sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" \
      podman inspect -f '{{.State.StartedAt}}' "${CONTAINER}"
  fi
}

_playbook_recap_changed() {
  local log="$1"
  sed -n 's/.*changed=\([0-9][0-9]*\).*/\1/p' "${log}" | tail -1
}

before="$(_container_started_at)"
log1="$(mktemp)"
log2="$(mktemp)"
trap 'rm -f "${log1}" "${log2}"' EXIT

printf 'First playbook pass...\n'
ansible-playbook -i "${INVENTORY}" site.yml >"${log1}" 2>&1 \
  || { tail -30 "${log1}"; fail "first playbook pass failed"; }

mid="$(_container_started_at)"

printf 'Second playbook pass (must be convergent)...\n'
ansible-playbook -i "${INVENTORY}" site.yml >"${log2}" 2>&1 \
  || { tail -30 "${log2}"; fail "second playbook pass failed"; }

after="$(_container_started_at)"
changed2="$(_playbook_recap_changed "${log2}")"

[[ -n "${changed2}" ]] || fail "could not parse PLAY RECAP from second run"
[[ "${changed2}" -eq 0 ]] \
  || fail "second pass reported changed=${changed2} (expected 0)"

[[ "${mid}" == "${after}" ]] \
  || fail "container restarted between passes (StartedAt ${mid} -> ${after})"

if [[ "${SKIP_MFA_CHECK:-0}" != "1" ]]; then
  if [[ "${_use_lima}" -eq 1 ]]; then
    limactl shell "${LIMA_INSTANCE}" -- sudo bash -lc "${ROOT}/scripts/test-mfa-preserve.sh" \
      || fail "MFA secret changed across idempotent deploy"
  else
    sudo bash -lc "${ROOT}/scripts/test-mfa-preserve.sh" \
      || fail "MFA secret changed across idempotent deploy"
  fi
fi

pass "two-pass deploy changed=0; container StartedAt stable; MFA preserved"
