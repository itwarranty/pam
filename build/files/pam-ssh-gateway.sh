#!/bin/sh
# Gateway SSH client session — PTY capture via script(1).
set -eu

TARGET_ID="${1:?target id}"
LOG="${3:?log path}"

exec script -q -f -c "/usr/local/bin/pam-ssh-gateway-exec.sh ${TARGET_ID}" "${LOG}"
