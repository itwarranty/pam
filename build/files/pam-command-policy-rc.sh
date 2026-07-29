#!/bin/bash
# Sourced via bash --rcfile when command policy denylist is mounted.
PAM_DENYLIST="${PAM_DENYLIST:-/run/ssh-pam/command_denylist}"
[ -r "${PAM_DENYLIST}" ] || PAM_DENYLIST="/etc/ssh-pam/command_denylist"

_pam_policy_debug() {
  local cmd="${BASH_COMMAND}"
  case "${cmd}" in
    _pam_*|trap\ *|true|:|'['*) return 0 ;;
  esac
  [ -r "${PAM_DENYLIST}" ] || return 0
  local pat
  while IFS= read -r pat || [ -n "${pat}" ]; do
    [ -z "${pat}" ] && continue
    case "${pat}" in \#*) continue ;; esac
    if [[ "${cmd}" =~ ${pat} ]]; then
      mode="${PAM_GATEWAY_MODE:-shell}"
      /usr/local/bin/pam-syslog.sh pam-deny "user=${USER:-unknown} mode=${mode} denied cmd=${cmd} pattern=${pat}"
      printf '[SSH PAM CSO] Command denied by shell policy.\n' >&2
      return 1
    fi
  done < "${PAM_DENYLIST}"
}

trap '_pam_policy_debug' DEBUG
