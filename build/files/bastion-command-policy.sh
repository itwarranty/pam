#!/bin/bash
# Launches login bash with DEBUG-trap denylist (shell role only).
set -euo pipefail

if [ ! -f /etc/bastion/command_denylist ]; then
  exec "$@"
fi

export BASTION_DENYLIST=/etc/bastion/command_denylist
exec bash --rcfile /usr/local/bin/bastion-command-policy-rc.sh "$@"
