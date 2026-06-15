#!/bin/bash
# Sourced via bash --rcfile when command policy denylist is mounted.
BASTION_DENYLIST="${BASTION_DENYLIST:-/etc/bastion/command_denylist}"

_mt_bastion_policy_debug() {
  local cmd="${BASH_COMMAND}"
  case "${cmd}" in
    _mt_bastion_*|trap\ *|true|:|'['*) return 0 ;;
  esac
  [ -r "${BASTION_DENYLIST}" ] || return 0
  local pat
  while IFS= read -r pat || [ -n "${pat}" ]; do
    [ -z "${pat}" ] && continue
    case "${pat}" in \#*) continue ;; esac
    if [[ "${cmd}" =~ ${pat} ]]; then
      logger -t mt-bastion-deny "user=${USER:-unknown} denied cmd=${cmd} pattern=${pat}"
      printf '[MT Bastion CSO] Command denied by shell policy.\n' >&2
      return 1
    fi
  done < "${BASTION_DENYLIST}"
}

trap '_mt_bastion_policy_debug' DEBUG
