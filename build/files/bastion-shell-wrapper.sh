#!/bin/sh
# Обёртка ForceCommand для интерактивных shell-сессий (не для ProxyJump).
set -eu

LOG="/var/log/bastion_sessions/session_${USER}_$(date +%Y%m%d_%H%M%S).log"
touch "${LOG}"
chattr +a "${LOG}" 2>/dev/null || true

logger -t mt-bastion "shell session start user=${USER} log=${LOG} client=${SSH_CLIENT:-unknown}"
exec script -q -f -c "/bin/bash --login" "${LOG}"
