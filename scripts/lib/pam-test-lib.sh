#!/usr/bin/env bash
# Shared helpers for acceptance tests (gateway host vs Mac+Lima).
set -euo pipefail

pam_test_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

pam_test_inventory() {
  if [[ -n "${PAM_ANSIBLE_INVENTORY:-}" ]]; then
    printf '%s\n' "${PAM_ANSIBLE_INVENTORY}"
    return
  fi
  if [[ -f /etc/redhat-release ]] && grep -qiE 'Rocky Linux release 9\.' /etc/redhat-release; then
    printf '%s\n' "inventory/localhost-lima.yml"
  else
    printf '%s\n' "inventory/local-lima.yml"
  fi
}

pam_test_on_gateway() {
  [[ -f /etc/redhat-release ]] && grep -qiE 'Rocky Linux release 9\.' /etc/redhat-release
}

pam_test_run_gateway() {
  local cmd="$1"
  if pam_test_on_gateway; then
    sudo bash -lc "${cmd}"
  else
    limactl shell "${LIMA_INSTANCE:-pam-prod}" -- sudo bash -lc "${cmd}"
  fi
}

pam_test_ansible() {
  local extra="${*:-}"
  local inv
  inv="$(pam_test_inventory)"
  if pam_test_on_gateway; then
    ansible-playbook -i "${inv}" site.yml ${extra}
  else
    limactl shell "${LIMA_INSTANCE:-pam-prod}" -- bash -lc \
      "export HOME=\"${HOME}\"; cd \"${ROOT:-$(pam_test_root)}\"; ansible-playbook -i inventory/localhost-lima.yml site.yml ${extra}"
  fi
}
