#!/usr/bin/env bash
# SSH PAM — post-deploy compliance verify (host-local).
# Mirrors tasks/verify_compliance_cso.yml. Exit 0 = pass, 1 = any failure.
#
# Usage (on Rocky 9 gateway host or via limactl shell):
#   ./scripts/pam-compliance-verify.sh
#   ./scripts/pam-compliance-verify.sh --json
#
# Env overrides:
#   PAM_USER, PAM_SSH_PORT, AUDIT_LOG_DIR, OPERATORS_HOME,
#   PAM_IMAGE_NAME, PAM_IMAGE_TAG, PAM_REQUIRED_MFA_LABEL,
#   PAM_SHELL_COMMAND_POLICY_ENABLED, PAM_COMMAND_POLICY_V2_REQUIRED,
#   PAM_AUDIT_LOG_DIR_MODE (dev lab gateway: 1777 per group_vars/dev/gateway_lab.yml)

set -euo pipefail

PAM_USER="${PAM_USER:-pam}"
PAM_SSH_PORT="${PAM_SSH_PORT:-2222}"
AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/pam_sessions}"
OPERATORS_HOME="${OPERATORS_HOME:-/home/${PAM_USER}/operators}"
PAM_IMAGE_NAME="${PAM_IMAGE_NAME:-pam_secure}"
PAM_IMAGE_TAG="${PAM_IMAGE_TAG:-latest}"
PAM_REQUIRED_MFA_LABEL="${PAM_REQUIRED_MFA_LABEL:-1}"
CONTAINER_NAME="${PAM_CONTAINER_NAME:-ssh_pam}"
PAM_TARGETS_HOME="${PAM_TARGETS_HOME:-/home/${PAM_USER}/targets}"
PAM_SESSION_SEARCH_ENABLED="${PAM_SESSION_SEARCH_ENABLED:-false}"
PAM_REQUIRE_FIDO_PUBKEY="${PAM_REQUIRE_FIDO_PUBKEY:-false}"
PAM_FIDO_ECDSA_SK_ALLOWED="${PAM_FIDO_ECDSA_SK_ALLOWED:-false}"
PAM_FIDO_WAIVER_OPERATORS="${PAM_FIDO_WAIVER_OPERATORS:-}"
PAM_SHELL_COMMAND_POLICY_ENABLED="${PAM_SHELL_COMMAND_POLICY_ENABLED:-true}"
PAM_COMMAND_POLICY_V2_REQUIRED="${PAM_COMMAND_POLICY_V2_REQUIRED:-true}"

JSON_MODE=0
for arg in "$@"; do
  case "${arg}" in
    --json|-j) JSON_MODE=1 ;;
    -h|--help)
      printf 'Usage: %s [--json]\n' "$0"
      exit 0
      ;;
  esac
done

PASS=0
FAIL=0
declare -a FAILED_CHECKS=()
declare -a PASSED_CHECKS=()

log_pass() {
  PASSED_CHECKS+=("$*")
  PASS=$((PASS + 1))
  [[ "${JSON_MODE}" -eq 1 ]] || printf '[PASS] %s\n' "$*"
}
log_fail() {
  FAILED_CHECKS+=("$*")
  FAIL=$((FAIL + 1))
  [[ "${JSON_MODE}" -eq 1 ]] || printf '[FAIL] %s\n' "$*" >&2
}

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

pam_runtime_dir() {
  local uid
  uid="$(getent passwd "${PAM_USER}" | cut -d: -f3)"
  printf '/run/user/%s' "${uid}"
}

run_as_pam() {
  local rt
  rt="$(pam_runtime_dir)"
  sudo runuser -u "${PAM_USER}" -- env "XDG_RUNTIME_DIR=${rt}" "$@"
}

check_container() {
  local running
  if ! running="$(run_as_pam podman inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null)"; then
    log_fail "container — ${CONTAINER_NAME} not found"
    return
  fi
  if [[ "${running}" == "true" ]]; then
    log_pass "container — ${CONTAINER_NAME} running as ${PAM_USER}"
  else
    log_fail "container — ${CONTAINER_NAME} not running"
  fi
}

check_mfa_label() {
  local label
  if ! label="$(run_as_pam podman image inspect "${PAM_IMAGE_NAME}:${PAM_IMAGE_TAG}" \
    --format '{{ index .Config.Labels "pam.mfa.strict" }}' 2>/dev/null)"; then
    log_fail "mfa_label — image ${PAM_IMAGE_NAME}:${PAM_IMAGE_TAG} not found"
    return
  fi
  if [[ "${label}" == "${PAM_REQUIRED_MFA_LABEL}" ]]; then
    log_pass "mfa_label — pam.mfa.strict=${label}"
  else
    log_fail "mfa_label — expected ${PAM_REQUIRED_MFA_LABEL}, got ${label:-empty}"
  fi
}

check_whitelist() {
  local cfg="/home/${PAM_USER}/.ssh_config/sshd_config"
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
  done < <(run_as_pam podman exec "${CONTAINER_NAME}" sh -c 'ls -1 /home 2>/dev/null || true' 2>/dev/null || true)
  orphans="$(echo "${orphans}" | xargs)"
  if [[ -z "${orphans}" ]]; then
    log_pass "orphan_users — no unexpected /home users in container"
  else
    log_fail "orphan_users — unexpected: ${orphans}"
  fi
}

check_service() {
  local name="$1"
  if ! command -v systemctl >/dev/null 2>&1; then
    log_fail "${name} — systemctl not available (run on Rocky 9 gateway host)"
    return
  fi
  if systemctl is-active --quiet "${name}"; then
    log_pass "${name} — active"
  else
    log_fail "${name} — not active"
  fi
}

check_session_log_dir() {
  local owner mode group
  if [[ ! -d "${AUDIT_LOG_DIR}" ]]; then
    log_fail "session_log_dir — ${AUDIT_LOG_DIR} missing"
    return
  fi
  owner="$(stat -c '%U' "${AUDIT_LOG_DIR}")"
  group="$(stat -c '%G' "${AUDIT_LOG_DIR}")"
  mode="$(stat -c '%a' "${AUDIT_LOG_DIR}")"
  if [[ "${owner}" == "${PAM_USER}" && "${mode}" == "${PAM_AUDIT_LOG_DIR_MODE:-750}" ]]; then
    log_pass "session_log_dir — ${AUDIT_LOG_DIR} ${mode} ${PAM_USER}"
  else
    log_fail "session_log_dir — expected ${PAM_AUDIT_LOG_DIR_MODE:-750} ${PAM_USER}, got ${mode} ${owner}"
  fi
  if [[ -f "${AUDIT_LOG_DIR}/gateway.syslog" ]]; then
    mode="$(stat -c '%a' "${AUDIT_LOG_DIR}/gateway.syslog")"
    owner="$(stat -c '%U' "${AUDIT_LOG_DIR}/gateway.syslog")"
    group="$(stat -c '%G' "${AUDIT_LOG_DIR}/gateway.syslog")"
    if [[ "${mode}" == "${PAM_AUDIT_LOG_FILE_MODE:-640}" && "${owner}" == "${PAM_USER}" ]]; then
      log_pass "gateway_syslog — mode ${mode} owner ${owner} group ${group}"
    else
      log_fail "gateway_syslog — expected ${PAM_AUDIT_LOG_FILE_MODE:-640} ${PAM_USER}, got ${mode} ${owner}:${group}"
    fi
  fi
}

check_firewall_port() {
  if firewall-cmd --query-port="${PAM_SSH_PORT}/tcp" >/dev/null 2>&1; then
    log_pass "firewall_port — ${PAM_SSH_PORT}/tcp open"
  elif firewall-cmd --list-rich-rules 2>/dev/null | grep -q "${PAM_SSH_PORT}"; then
    log_pass "firewall_port — rich rules for ${PAM_SSH_PORT}/tcp"
  else
    log_fail "firewall_port — ${PAM_SSH_PORT}/tcp not allowed"
  fi
}

check_rate_limit() {
  [[ "${PAM_SSH_RATE_LIMIT_ENABLED:-false}" != "true" ]] && return 0
  local method="${PAM_SSH_RATE_LIMIT_METHOD:-firewalld}"
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
  local manifest="${PAM_TARGETS_HOME}/manifest.json"
  if [[ ! -f "${manifest}" ]]; then
    if [[ "${PAM_GATEWAY_TARGETS_EXPECTED:-false}" == "true" ]]; then
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
  [[ "${PAM_SESSION_SEARCH_ENABLED}" != "true" ]] && return 0
  if command -v jq >/dev/null 2>&1; then
    log_pass "jq — installed (session search enabled)"
  else
    log_fail "jq — required when PAM_SESSION_SEARCH_ENABLED=true"
  fi
}

check_tier4_cli() {
  [[ "${PAM_SESSION_SEARCH_ENABLED}" != "true" ]] && return 0
  if [[ -x /usr/local/bin/pam-session-search ]]; then
    log_pass "tier4_cli — pam-session-search installed"
  else
    log_fail "tier4_cli — pam-session-search missing"
  fi
}

check_command_policy_v2() {
  [[ "${PAM_COMMAND_POLICY_V2_REQUIRED}" != "true" ]] && return 0
  [[ "${PAM_SHELL_COMMAND_POLICY_ENABLED}" != "true" ]] && return 0

  local missing=""
  if ! run_as_pam podman exec "${CONTAINER_NAME}" test -f /usr/local/bin/pam-pty-inspector.py 2>/dev/null; then
    log_fail "command_policy_v2 — pam-pty-inspector.py missing (python3 required in image)"
    return
  fi
  if ! run_as_pam podman exec "${CONTAINER_NAME}" test -f /run/ssh-pam/policy_v2_enabled 2>/dev/null; then
    missing="gateway"
  fi
  if ! run_as_pam podman exec "${CONTAINER_NAME}" test -f /run/ssh-pam/shell_policy_v2_enabled 2>/dev/null; then
    missing="${missing:+$missing, }shell"
  fi
  if [[ -n "${missing}" ]]; then
    log_fail "command_policy_v2 — PTY inspector v2 not active (${missing}); set PAM_COMMAND_POLICY_V2_REQUIRED=false only for migration"
    return
  fi
  log_pass "command_policy_v2 — gateway + shell PTY inspector active (CSO prod policy)"
}

check_fido_pubkey() {
  [[ "${PAM_REQUIRE_FIDO_PUBKEY}" != "true" ]] && return 0
  local script="${PAM_FIDO_CHECK_SCRIPT:-/usr/local/lib/ssh-pam/preflight-fido-key.py}"
  local waiver=" ${PAM_FIDO_WAIVER_OPERATORS} "
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
    if PAM_FIDO_ECDSA_SK_ALLOWED="${PAM_FIDO_ECDSA_SK_ALLOWED}" \
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
  [[ "${JSON_MODE}" -eq 1 ]] || printf '=== SSH PAM compliance verify ===\n\n'
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

  if [[ "${JSON_MODE}" -eq 1 ]]; then
    PASS_FILE="$(mktemp)"
    FAIL_FILE="$(mktemp)"
    printf '%s\n' "${PASSED_CHECKS[@]:-}" > "${PASS_FILE}"
    printf '%s\n' "${FAILED_CHECKS[@]:-}" > "${FAIL_FILE}"
    python3 - "${PASS}" "${FAIL}" "${PASS_FILE}" "${FAIL_FILE}" <<'PY'
import json, sys
from pathlib import Path
pass_n, fail_n = int(sys.argv[1]), int(sys.argv[2])
passed = [l for l in Path(sys.argv[3]).read_text().splitlines() if l]
failed = [l for l in Path(sys.argv[4]).read_text().splitlines() if l]
print(json.dumps({
    "product": "ITWarranty SSH PAM",
    "passed": pass_n,
    "failed": fail_n,
    "ok": fail_n == 0,
    "passed_checks": passed,
    "failed_checks": failed,
}, ensure_ascii=False, indent=2))
PY
    rm -f "${PASS_FILE}" "${FAIL_FILE}"
  else
    printf '\n=== Summary: %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
    if [[ "${FAIL}" -gt 0 ]]; then
      printf 'Failed checks: %s\n' "${FAILED_CHECKS[*]}" >&2
    else
      printf 'All compliance checks PASSED.\n'
    fi
  fi
  [[ "${FAIL}" -eq 0 ]] || exit 1
}

main
