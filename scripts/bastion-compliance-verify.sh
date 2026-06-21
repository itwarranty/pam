#!/usr/bin/env bash
# SSH PAM — post-deploy compliance verify (host-local).
# Mirrors tasks/verify_compliance_cso.yml. Exit 0 = pass, 1 = any failure.
#
# Usage (on Rocky 9 bastion host or via limactl shell):
#   ./scripts/bastion-compliance-verify.sh
#
# Env overrides:
#   BASTION_USER, BASTION_SSH_PORT, AUDIT_LOG_DIR, OPERATORS_HOME,
#   BASTION_IMAGE_NAME, BASTION_IMAGE_TAG, BASTION_REQUIRED_MFA_LABEL,
#   BASTION_SHELL_COMMAND_POLICY_ENABLED, BASTION_COMMAND_POLICY_V2_REQUIRED,
#   BASTION_AUDIT_LOG_DIR_MODE (dev lab gateway: 1777 per group_vars/dev/gateway_lab.yml)

set -euo pipefail

BASTION_USER="${BASTION_USER:-bastion}"
BASTION_SSH_PORT="${BASTION_SSH_PORT:-2222}"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/bastion_sessions}"
OPERATORS_HOME="${OPERATORS_HOME:-/home/${BASTION_USER}/operators}"
BASTION_IMAGE_NAME="${BASTION_IMAGE_NAME:-bastion_secure}"
BASTION_IMAGE_TAG="${BASTION_IMAGE_TAG:-latest}"
BASTION_REQUIRED_MFA_LABEL="${BASTION_REQUIRED_MFA_LABEL:-1}"
CONTAINER_NAME="${BASTION_CONTAINER_NAME:-ssh_bastion}"
BASTION_TARGETS_HOME="${BASTION_TARGETS_HOME:-/home/${BASTION_USER}/targets}"
BASTION_SESSION_SEARCH_ENABLED="${BASTION_SESSION_SEARCH_ENABLED:-false}"
BASTION_REQUIRE_FIDO_PUBKEY="${BASTION_REQUIRE_FIDO_PUBKEY:-false}"
BASTION_FIDO_ECDSA_SK_ALLOWED="${BASTION_FIDO_ECDSA_SK_ALLOWED:-false}"
BASTION_FIDO_WAIVER_OPERATORS="${BASTION_FIDO_WAIVER_OPERATORS:-}"
BASTION_SHELL_COMMAND_POLICY_ENABLED="${BASTION_SHELL_COMMAND_POLICY_ENABLED:-true}"
BASTION_COMMAND_POLICY_V2_REQUIRED="${BASTION_COMMAND_POLICY_V2_REQUIRED:-true}"

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
    --format '{{ index .Config.Labels "bastion.mfa.strict" }}' 2>/dev/null)"; then
    log_fail "mfa_label — image ${BASTION_IMAGE_NAME}:${BASTION_IMAGE_TAG} not found"
    return
  fi
  if [[ "${label}" == "${BASTION_REQUIRED_MFA_LABEL}" ]]; then
    log_pass "mfa_label — bastion.mfa.strict=${label}"
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
  if [[ "${owner}" == "${BASTION_USER}" && "${mode}" == "${BASTION_AUDIT_LOG_DIR_MODE:-750}" ]]; then
    log_pass "session_log_dir — ${AUDIT_LOG_DIR} ${mode} ${BASTION_USER}"
  else
    log_fail "session_log_dir — expected ${BASTION_AUDIT_LOG_DIR_MODE:-750} ${BASTION_USER}, got ${mode} ${owner}"
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

check_rate_limit() {
  [[ "${BASTION_SSH_RATE_LIMIT_ENABLED:-false}" != "true" ]] && return 0
  local method="${BASTION_SSH_RATE_LIMIT_METHOD:-firewalld}"
  if [[ "${method}" == "firewalld" ]]; then
    if firewall-cmd --list-rich-rules 2>/dev/null | grep -q 'limit value'; then
      log_pass "rate_limit — firewalld limit rule present"
    else
      log_fail "rate_limit — firewalld limit rule missing"
    fi
  elif systemctl is-active --quiet fail2ban 2>/dev/null; then
    log_pass "rate_limit — fail2ban active"
  else
    log_fail "rate_limit — fail2ban not active"
  fi
}

check_gateway_manifest() {
  local manifest="${BASTION_TARGETS_HOME}/manifest.json"
  if [[ ! -f "${manifest}" ]]; then
    if [[ "${BASTION_GATEWAY_TARGETS_EXPECTED:-false}" == "true" ]]; then
      log_fail "gateway_targets — manifest.json missing at ${manifest}"
    fi
    return 0
  fi
  if command -v jq >/dev/null 2>&1 && jq -e '.targets | type == "array"' "${manifest}" >/dev/null 2>&1; then
    log_pass "gateway_targets — manifest.json valid"
  elif grep -q '"targets"' "${manifest}" 2>/dev/null; then
    log_pass "gateway_targets — manifest.json present"
  else
    log_fail "gateway_targets — manifest.json invalid"
  fi
}

check_jq_optional() {
  [[ "${BASTION_SESSION_SEARCH_ENABLED}" != "true" ]] && return 0
  if command -v jq >/dev/null 2>&1; then
    log_pass "jq — installed (session search enabled)"
  else
    log_fail "jq — required when BASTION_SESSION_SEARCH_ENABLED=true"
  fi
}

check_tier4_cli() {
  [[ "${BASTION_SESSION_SEARCH_ENABLED}" != "true" ]] && return 0
  if [[ -x /usr/local/bin/bastion-session-search ]]; then
    log_pass "tier4_cli — bastion-session-search installed"
  else
    log_fail "tier4_cli — bastion-session-search missing"
  fi
}

check_command_policy_v2() {
  [[ "${BASTION_COMMAND_POLICY_V2_REQUIRED}" != "true" ]] && return 0
  [[ "${BASTION_SHELL_COMMAND_POLICY_ENABLED}" != "true" ]] && return 0

  local missing=""
  if ! run_as_bastion podman exec "${CONTAINER_NAME}" test -f /usr/local/bin/bastion-pty-inspector.py 2>/dev/null; then
    log_fail "command_policy_v2 — bastion-pty-inspector.py missing (python3 required in image)"
    return
  fi
  if ! run_as_bastion podman exec "${CONTAINER_NAME}" test -f /run/bastion/policy_v2_enabled 2>/dev/null; then
    missing="gateway"
  fi
  if ! run_as_bastion podman exec "${CONTAINER_NAME}" test -f /run/bastion/shell_policy_v2_enabled 2>/dev/null; then
    missing="${missing:+$missing, }shell"
  fi
  if [[ -n "${missing}" ]]; then
    log_fail "command_policy_v2 — PTY inspector v2 not active (${missing}); set BASTION_COMMAND_POLICY_V2_REQUIRED=false only for migration"
    return
  fi
  log_pass "command_policy_v2 — gateway + shell PTY inspector active (CSO prod policy)"
}

check_fido_pubkey() {
  [[ "${BASTION_REQUIRE_FIDO_PUBKEY}" != "true" ]] && return 0
  local script="${BASTION_FIDO_CHECK_SCRIPT:-/usr/local/lib/bastion/preflight-fido-key.py}"
  local waiver=" ${BASTION_FIDO_WAIVER_OPERATORS} "
  local op ak line name failures=0

  if [[ ! -f "${script}" ]]; then
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/preflight-fido-key.py"
  fi
  if [[ ! -f "${script}" ]]; then
    log_fail "fido_pubkey — preflight-fido-key.py not found"
    return
  fi

  if [[ ! -d "${OPERATORS_HOME}" ]]; then
    log_fail "fido_pubkey — operators home missing: ${OPERATORS_HOME}"
    return
  fi

  for opdir in "${OPERATORS_HOME}"/*; do
    [[ -d "${opdir}" ]] || continue
    name="$(basename "${opdir}")"
    case "${waiver}" in
      *" ${name} "*) continue ;;
    esac
    ak="${opdir}/.ssh/authorized_keys"
    [[ -f "${ak}" ]] || { log_fail "fido_pubkey — ${name}: authorized_keys missing"; failures=$((failures + 1)); continue; }
    line="$(grep -v '^#' "${ak}" | head -1 || true)"
    if [[ -z "${line}" ]]; then
      log_fail "fido_pubkey — ${name}: empty authorized_keys"
      failures=$((failures + 1))
      continue
    fi
    if BASTION_FIDO_ECDSA_SK_ALLOWED="${BASTION_FIDO_ECDSA_SK_ALLOWED}" \
      python3 "${script}" "${line}" >/dev/null 2>&1; then
      :
    else
      log_fail "fido_pubkey — ${name}: not FIDO-sk backed"
      failures=$((failures + 1))
    fi
  done

  if [[ "${failures}" -eq 0 ]]; then
    log_pass "fido_pubkey — all operators use FIDO-sk keys or certs (CSO policy)"
  fi
}

main() {
  printf '=== SSH PAM compliance verify ===\n\n'
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
  check_rate_limit
  check_gateway_manifest
  check_jq_optional
  check_tier4_cli
  check_command_policy_v2
  check_fido_pubkey

  printf '\n=== Summary: %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
  if [[ "${FAIL}" -gt 0 ]]; then
    printf 'Failed checks: %s\n' "${FAILED_CHECKS[*]}" >&2
    exit 1
  fi
  printf 'All compliance checks PASSED.\n'
}

main "$@"
