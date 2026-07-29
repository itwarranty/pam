#!/bin/sh
# Shown when jump operator requests interactive shell (PermitTTY + mistaken direct ssh).
# ProxyJump (-W) does not execute this — forwarding uses separate channel.
set -eu

PERMIT="/home/${USER}/permit_open"
PORT="${PAM_SSH_PORT:-2222}"

printf '\n'
printf '╔══════════════════════════════════════════════════════════════╗\n'
printf '║  SSH PAM — access: jump                                   ║\n'
printf '╠══════════════════════════════════════════════════════════════╣\n'
printf '║  Interactive shell on the gateway is disabled.             ║\n'
printf '║  Use ProxyJump (-J), not direct ssh to this account.         ║\n'
printf '║                                                              ║\n'

if [ -f "${PERMIT}" ]; then
  printf '║  PermitOpen:                                                 ║\n'
  while read -r line || [ -n "${line}" ]; do
  line="$(printf '%s' "${line}" | tr -d '\r')"
  [ -n "${line}" ] || continue
  printf '║    %-56s ║\n' "${line}"
  done < "${PERMIT}"
  first="$(head -1 "${PERMIT}" | tr -d '\r')"
  if [ -n "${first}" ]; then
    host="${first%%:*}"
    tport="${first##*:}"
    printf '║                                                              ║\n'
    printf '║  Example:                                                    ║\n'
    printf '║    ssh -J %s@HOST:%s user@%s                       ║\n' "${USER}" "${PORT}" "${host}"
  fi
else
  printf '║  (permit_open file not found)                                ║\n'
fi

printf '║                                                              ║\n'
printf '║  On your Mac: ./scripts/pam-doctor.sh %s              ║\n' "${USER}"
printf '╚══════════════════════════════════════════════════════════════╝\n'
printf '\n'

exit 0
