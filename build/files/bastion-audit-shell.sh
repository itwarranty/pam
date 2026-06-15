#!/bin/bash
# Restricted read-only shell for access: audit (paths under /var/log/bastion_sessions only).
set -euo pipefail

AUDIT_DIR=/var/log/bastion_sessions
ALLOWED_CMDS='less|cat|ls|head|tail|grep|sha256sum|pwd|exit|echo|help'

_audit_resolve_path() {
  local arg="$1"
  local resolved
  resolved="$(realpath -m "${arg}" 2>/dev/null || true)"
  [ -n "${resolved}" ] || return 1
  case "${resolved}" in
    "${AUDIT_DIR}"|"${AUDIT_DIR}"/*) printf '%s' "${resolved}"; return 0 ;;
  esac
  return 1
}

_audit_check_line() {
  local line="$1"
  local cmd args rest
  read -r cmd args <<<"${line}"
  [ -n "${cmd}" ] || return 0

  case "${cmd}" in
    exit|logout) exit 0 ;;
    help)
      echo "Allowed: less, cat, ls, head, tail, grep, sha256sum, pwd, exit"
      echo "Paths must be under ${AUDIT_DIR}"
      return 0
      ;;
  esac

  if ! [[ "${cmd}" =~ ^(${ALLOWED_CMDS})$ ]]; then
    logger -t mt-bastion-deny "audit user=${USER} denied cmd=${cmd}"
    echo "[MT Bastion CSO] Command not permitted for audit role." >&2
    return 1
  fi

  case "${cmd}" in
    ls|pwd|exit|help) ;;
    tail)
      if [[ "${args}" == *"-f"* ]] || [[ "${args}" == *"-F"* ]]; then
        echo "[MT Bastion CSO] tail -f not permitted (audit read-only)." >&2
        return 1
      fi
      for p in ${args}; do
        case "${p}" in -*) continue ;; esac
        _audit_resolve_path "${p}" >/dev/null || { echo "[MT Bastion CSO] Path denied." >&2; return 1; }
      done
      ;;
    *)
      for p in ${args}; do
        case "${p}" in -*) continue ;; esac
        _audit_resolve_path "${p}" >/dev/null || { echo "[MT Bastion CSO] Path denied." >&2; return 1; }
      done
      ;;
  esac

  if [[ "${line}" == *">"* ]] || [[ "${line}" == *"<"* ]]; then
    echo "[MT Bastion CSO] Redirection not permitted." >&2
    return 1
  fi

  eval "${line}"
}

echo "MT Bastion audit shell — read-only under ${AUDIT_DIR}. Type 'help' or 'exit'."
while true; do
  read -e -r -p "audit> " line || break
  [ -z "${line}" ] && continue
  _audit_check_line "${line}" || true
done
