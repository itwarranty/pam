#!/bin/bash
# Launches login bash with DEBUG-trap denylist (shell role only).
set -euo pipefail

if [ ! -f /etc/ssh-pam/command_denylist ]; then
  exec "$@"
fi

export PAM_DENYLIST=/etc/ssh-pam/command_denylist
exec bash --rcfile /usr/local/bin/pam-command-policy-rc.sh "$@"
