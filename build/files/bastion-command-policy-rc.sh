#!/bin/bash
# Sourced via bash --rcfile when command policy denylist is mounted.
BASTION_DENYLIST="${BASTION_DENYLIST:-/run/bastion/command_denylist}"
[ -r "${BASTION_DENYLIST}" ] || BASTION_DENYLIST="/etc/bastion/command_denylist"

_bastion_policy_debug() {
  local cmd="${BASH_COMMAND}"
  case "${cmd}" in
    _bastion_*|trap\ *|true|:|'['*) return 0 ;;
  esac
  [ -r "${BASTION_DENYLIST}" ] || return 0
  local pat
  while IFS= read -r pat || [ -n "${pat}" ]; do
    [ -z "${pat}" ] && continue
    case "${pat}" in \#*) continue ;; esac
    if [[ "${cmd}" =~ ${pat} ]]; then
      mode="${BASTION_GATEWAY_MODE:-shell}"
      /usr/local/bin/bastion-syslog.sh bastion-deny "user=${USER:-unknown} mode=${mode} denied cmd=${cmd} pattern=${pat}"
      printf '[SSH PAM CSO] Command denied by shell policy.\n' >&2
      return 1
    fi
  done < "${BASTION_DENYLIST}"
}

trap '_bastion_policy_debug' DEBUG
