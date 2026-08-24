#!/bin/sh
# Invoked inside script(1) — runs ssh to target (policy v2 gateway-side or v1 remote rc).
set -eu

TARGET_ID="${1:?target id}"
export PAM_GATEWAY_MODE=gateway
TARGETS_ROOT="${PAM_TARGETS_DIR:-/run/ssh-pam/targets-runtime}"
[ -d "${TARGETS_ROOT}" ] || TARGETS_ROOT="/etc/ssh-pam/targets"
USER_HOME="/home/${LOGNAME:-${USER}}"
if [ -f "${USER_HOME}/.itwarranty-pam/targets/${TARGET_ID}/target.env" ]; then
  # shellcheck disable=SC1090
  . "${USER_HOME}/.itwarranty-pam/targets/${TARGET_ID}/target.env"
  IDENTITY="${USER_HOME}/.itwarranty-pam/targets/${TARGET_ID}/identity"
  KNOWN="${USER_HOME}/.itwarranty-pam/known_hosts"
  [ -f "${KNOWN}" ] || KNOWN="${TARGETS_ROOT}/known_hosts"
else
  # shellcheck disable=SC1090
  . "${TARGETS_ROOT}/${TARGET_ID}/target.env"
  IDENTITY="${TARGETS_ROOT}/${TARGET_ID}/identity"
  KNOWN="${TARGETS_ROOT}/known_hosts"
fi

SSH_OPTS="-i ${IDENTITY} -p ${PORT} -o LogLevel=ERROR -o UserKnownHostsFile=${KNOWN}"

if [ -f /run/ssh-pam/lab_mode ] || [ "${PAM_GATEWAY_LAB_MODE:-0}" = "1" ]; then
  PAM_GATEWAY_LAB_MODE=1
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=accept-new"
else
  SSH_OPTS="${SSH_OPTS} -o StrictHostKeyChecking=yes"
fi

if [ -f /run/ssh-pam/policy_v2_enabled ] || [ "${PAM_GATEWAY_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ]; then
  PAM_GATEWAY_COMMAND_POLICY_V2_ENABLED=1
  if [ -f /run/ssh-pam/command_denylist ] || [ -f /etc/ssh-pam/command_denylist ]; then
    export PAM_DENYLIST=/run/ssh-pam/command_denylist
    [ -f "${PAM_DENYLIST}" ] || export PAM_DENYLIST=/etc/ssh-pam/command_denylist
    export PAM_GATEWAY_DENY_KILL="${PAM_GATEWAY_DENY_KILL_SESSION:-0}"
    # shellcheck disable=SC2086
    exec /usr/local/bin/pam-pty-inspector.sh ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
  fi
fi

if [ -f /run/ssh-pam/command_denylist ] || [ -f /etc/ssh-pam/command_denylist ]; then
  if [ -f /usr/local/bin/pam-command-policy-rc.sh ] && [ "${PAM_COMMAND_POLICY_V1_WAIVER:-0}" = "1" ]; then
  RC_B64="$(base64 -w 0 /usr/local/bin/pam-command-policy-rc.sh 2>/dev/null \
    || base64 /usr/local/bin/pam-command-policy-rc.sh | tr -d '\n')"
  # shellcheck disable=SC2086
  exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}" \
    "TMPRC=\$(mktemp /tmp/.pam-rc.XXXXXX); trap 'rm -f \"\${TMPRC}\"' EXIT; echo '${RC_B64}' | base64 -d > \"\${TMPRC}\"; exec bash --rcfile \"\${TMPRC}\" -i"
  fi
fi

# shellcheck disable=SC2086
exec ssh ${SSH_OPTS} -tt "${ACCOUNT}@${HOST}"
