#!/usr/bin/env bash
# MT: Bastion — post-deploy compliance verify (host-local).
# Mirrors tasks/verify_compliance_cso.yml. Exit 0 = pass, 1 = any failure.
#
# Usage (on Rocky 9 bastion host or via limactl shell):
#   ./scripts/bastion-compliance-verify.sh
#
# Env overrides:
#   BASTION_USER, BASTION_SSH_PORT, AUDIT_LOG_DIR, OPERATORS_HOME,
#   BASTION_IMAGE_NAME, BASTION_IMAGE_TAG, BASTION_REQUIRED_MFA_LABEL

set -euo pipefail

BASTION_USER="${BASTION_USER:-mt_bastion}"
BASTION_SSH_PORT="${BASTION_SSH_PORT:-2222}"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/bastion_sessions}"
OPERATORS_HOME="${OPERATORS_HOME:-/home/${BASTION_USER}/operators}"
BASTION_IMAGE_NAME="${BASTION_IMAGE_NAME:-mt_bastion_secure}"
BASTION_IMAGE_TAG="${BASTION_IMAGE_TAG:-latest}"
BASTION_REQUIRED_MFA_LABEL="${BASTION_REQUIRED_MFA_LABEL:-1}"
CONTAINER_NAME="${BASTION_CONTAINER_NAME:-mt_ssh_bastion}"

PASS=0
FAIL=0
declare -a FAILED_CHECKS=()

log_pass() { printf '[PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
log_fail() { printf '[FAIL] %s\n' "$*" >&2; FAIL=$((FAIL + 1)); FAILED_CHECKS+=("$1"); }

check_os() {
  if [[ -f /etc/redhat-release ]]; then
    if grep -qiE 'Rocky Linux release 9\.' /etc/redhat-release; then
      log_pass "os — Rocky Linux 9.x ($(tr -d '\n' < /etc/redhat-release))"
      return
    fi
  fi
  log_fail "os — Rocky Linux 9.x required"
}

check_arch() {
  local arch
  arch="$(uname -m)"
  if [[ "${arch}" == "x86_64" ]]; then
    log_pass "arch — ${arch}"
  else
    log_fail "arch — x86_64 required (got ${arch})"
  fi
}

check_selinux() {
  local mode
  mode="$(getenforce 2>/dev/null || echo unknown)"
  if [[ "${mode}" == "Enforcing" ]]; then
    log_pass "selinux — Enforcing"
  else
    log_fail "selinux — Enforcing required (got ${mode})"
  fi
}

bastion_runtime_dir() {
  local uid
  uid="$(getent passwd "${BASTION_USER}" | cut -d: -f3)"
  printf '/run/user/%s' "${uid}"
}

run_as_bastion() {
  local rt
  rt="$(bastion_runtime_dir)"
  sudo runuser -u "${BASTION_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

check_container() {
  local running
  if ! running="$(run_as_bastion podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)"; then
    log_fail "container — ${CONTAINER_NAME} not found"
    return
  fi
  if [[ "${running}" == "true" ]]; then
    log_pass "container — ${CONTAINER_NAME} running as ${BASTION_USER}"
  else
    log_fail "container — ${CONTAINER_NAME} not running"
  fi
}

check_mfa_label() {
  local label
  if ! label="$(run_as_bastion podman image inspect "${BASTION_IMAGE_NAME}:${BASTION_IMAGE_TAG}" \
    --format '{{ index .Config.Labels "mt.global.mfa.strict" }}' 2>/dev/null)"; then
    log_fail "mfa_label — image ${BASTION_IMAGE_NAME}:${BASTION_IMAGE_TAG} not found"
    return
  fi
  if [[ "${label}" == "${BASTION_REQUIRED_MFA_LABEL}" ]]; then
    log_pass "mfa_label — mt.global.mfa.strict=${label}"
  else
    log_fail "mfa_label — expected ${BASTION_REQUIRED_MFA_LABEL}, got ${label:-empty}"
  fi
}

check_whitelist() {
  local cfg="/home/${BASTION_USER}/.ssh_config/sshd_config"
  if [[ ! -f "${cfg}" ]]; then
    log_fail "whitelist — sshd_config not found at ${cfg}"
    return
  fi
  if grep -qE '^PermitOpen ' "${cfg}"; then
    log_pass "whitelist — PermitOpen entries present in deployed sshd_config"
  else
    log_fail "whitelist — no PermitOpen in ${cfg}"
  fi
}

check_orphan_users() {
  local allowed="" u orphans=""
  if [[ -d "${OPERATORS_HOME}" ]]; then
    for u in "${OPERATORS_HOME}"/*; do
      [[ -d "${u}" ]] || continue
      allowed="${allowed} $(basename "${u}") "
    done
  fi
  orphans=""
  while IFS= read -r u; do
    [[ -n "${u}" ]] || continue
    case "${allowed}" in
      *" ${u} "*) ;;
      *) orphans="${orphans} ${u}" ;;
    esac
  done < <(run_as_bastion podman exec "${CONTAINER_NAME}" sh -c 'ls -1 /home 2>/dev/null || true' 2>/dev/null || true)
  orphans="$(echo "${orphans}" | xargs)"
  if [[ -z "${orphans}" ]]; then
    log_pass "orphan_users — no unexpected /home users in container"
  else
    log_fail "orphan_users — unexpected: ${orphans}"
  fi
}

check_service() {
  local name="$1"
  if systemctl is-active --quiet "${name}"; then
    log_pass "${name} — active"
  else
    log_fail "${name} — not active"
  fi
}

check_session_log_dir() {
  local owner mode
  if [[ ! -d "${AUDIT_LOG_DIR}" ]]; then
    log_fail "session_log_dir — ${AUDIT_LOG_DIR} missing"
    return
  fi
  owner="$(stat -c '%U' "${AUDIT_LOG_DIR}")"
  mode="$(stat -c '%a' "${AUDIT_LOG_DIR}")"
  if [[ "${owner}" == "${BASTION_USER}" && "${mode}" == "750" ]]; then
    log_pass "session_log_dir — ${AUDIT_LOG_DIR} ${mode} ${BASTION_USER}"
  else
    log_fail "session_log_dir — expected 0750 ${BASTION_USER}, got ${mode} ${owner}"
  fi
}

check_firewall_port() {
  if firewall-cmd --query-port="${BASTION_SSH_PORT}/tcp" >/dev/null 2>&1; then
    log_pass "firewall_port — ${BASTION_SSH_PORT}/tcp open"
  elif firewall-cmd --list-rich-rules 2>/dev/null | grep -q "${BASTION_SSH_PORT}"; then
    log_pass "firewall_port — rich rules for ${BASTION_SSH_PORT}/tcp"
  else
    log_fail "firewall_port — ${BASTION_SSH_PORT}/tcp not allowed"
  fi
}

main() {
  printf '=== MT Bastion compliance verify ===\n\n'
  check_os
  check_arch
  check_selinux
  check_container
  check_mfa_label
  check_whitelist
  check_orphan_users
  check_service auditd
  check_service firewalld
  check_session_log_dir
  check_firewall_port

  printf '\n=== Summary: %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
  if [[ "${FAIL}" -gt 0 ]]; then
    printf 'Failed checks: %s\n' "${FAILED_CHECKS[*]}" >&2
    exit 1
  fi
  printf 'All compliance checks PASSED.\n'
}

main "$@"
