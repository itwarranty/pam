#!/bin/sh
# Invoked inside script(1) — runs ssh to target (policy v2 bastion-side or v1 remote rc).
set -eu

TARGET_ID="${1:?target id}"
export MT_BASTION_GATEWAY_MODE=gateway
. "/etc/bastion/targets/${TARGET_ID}/target.env"

IDENTITY="/etc/bastion/targets/${TARGET_ID}/identity"
KNOWN="/etc/bastion/targets/known_hosts"

SSH_OPTS="-i ${IDENTITY} -p ${PORT} -o LogLevel=ERROR -o UserKnownHostsFile=${KNOWN}"

if [ "${BASTION_GATEWAY_LAB_MODE:-0}" = "1" ]; then
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=accept-new"
else
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=yes"
fi

if [ -f /etc/bastion/command_denylist ] && [ "${BASTION_GATEWAY_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ]; then
  export BASTION_DENYLIST=/etc/bastion/command_denylist
  export BASTION_GATEWAY_DENY_KILL="${BASTION_GATEWAY_DENY_KILL_SESSION:-0}"
  # shellcheck disable=SC2086
  exec /usr/local/bin/bastion-pty-inspector.sh ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
fi

if [ -f /etc/bastion/command_denylist ] && [ -f /usr/local/bin/bastion-command-policy-rc.sh ]; then
  RC_B64="$(base64 -w 0 /usr/local/bin/bastion-command-policy-rc.sh 2>/dev/null \
    || base64 /usr/local/bin/bastion-command-policy-rc.sh | tr -d '\n')"
  # shellcheck disable=SC2086
  exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}" \
    "TMPRC=\$(mktemp /tmp/.mt-bastion-rc.XXXXXX); trap 'rm -f \"\${TMPRC}\"' EXIT; echo '${RC_B64}' | base64 -d > \"\${TMPRC}\"; exec bash --rcfile \"\${TMPRC}\" -i"
fi

# shellcheck disable=SC2086
exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
