#!/bin/sh
# Invoked inside script(1) — runs ssh to target (policy v2 bastion-side or v1 remote rc).
set -eu

TARGET_ID="${1:?target id}"
export BASTION_GATEWAY_MODE=gateway
TARGETS_ROOT="${BASTION_TARGETS_DIR:-/run/bastion/targets-runtime}"
[ -d "${TARGETS_ROOT}" ] || TARGETS_ROOT="/etc/bastion/targets"
USER_HOME="/home/${LOGNAME:-${USER}}"
if [ -f "${USER_HOME}/.bastion/targets/${TARGET_ID}/target.env" ]; then
  # shellcheck disable=SC1090
  . "${USER_HOME}/.bastion/targets/${TARGET_ID}/target.env"
  IDENTITY="${USER_HOME}/.bastion/targets/${TARGET_ID}/identity"
  KNOWN="${USER_HOME}/.bastion/known_hosts"
  [ -f "${KNOWN}" ] || KNOWN="${TARGETS_ROOT}/known_hosts"
else
  # shellcheck disable=SC1090
  . "${TARGETS_ROOT}/${TARGET_ID}/target.env"
  IDENTITY="${TARGETS_ROOT}/${TARGET_ID}/identity"
  KNOWN="${TARGETS_ROOT}/known_hosts"
fi

SSH_OPTS="-i ${IDENTITY} -p ${PORT} -o LogLevel=ERROR -o UserKnownHostsFile=${KNOWN}"

if [ -f /run/bastion/lab_mode ] || [ "${BASTION_GATEWAY_LAB_MODE:-0}" = "1" ]; then
  BASTION_GATEWAY_LAB_MODE=1
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=accept-new"
else
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=yes"
fi

if [ -f /run/bastion/policy_v2_enabled ] || [ "${BASTION_GATEWAY_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ]; then
  BASTION_GATEWAY_COMMAND_POLICY_V2_ENABLED=1
  if [ -f /run/bastion/command_denylist ] || [ -f /etc/bastion/command_denylist ]; then
    export BASTION_DENYLIST=/run/bastion/command_denylist
    [ -f "${BASTION_DENYLIST}" ] || export BASTION_DENYLIST=/etc/bastion/command_denylist
    export BASTION_GATEWAY_DENY_KILL="${BASTION_GATEWAY_DENY_KILL_SESSION:-0}"
    # shellcheck disable=SC2086
    exec /usr/local/bin/bastion-pty-inspector.sh ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
  fi
fi

if [ -f /run/bastion/command_denylist ] || [ -f /etc/bastion/command_denylist ]; then
  if [ -f /usr/local/bin/bastion-command-policy-rc.sh ]; then
  RC_B64="$(base64 -w 0 /usr/local/bin/bastion-command-policy-rc.sh 2>/dev/null \
    || base64 /usr/local/bin/bastion-command-policy-rc.sh | tr -d '\n')"
  # shellcheck disable=SC2086
  exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}" \
    "TMPRC=\$(mktemp /tmp/.bastion-rc.XXXXXX); trap 'rm -f \"\${TMPRC}\"' EXIT; echo '${RC_B64}' | base64 -d > \"\${TMPRC}\"; exec bash --rcfile \"\${TMPRC}\" -i"
  fi
fi

# shellcheck disable=SC2086
exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
