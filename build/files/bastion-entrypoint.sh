#!/bin/sh
# Создаёт системных пользователей из смонтированных домашних каталогов и запускает sshd.
set -eu

if [ -d /home ]; then
  for home_dir in /home/*; do
    [ -d "${home_dir}" ] || continue
    username="$(basename "${home_dir}")"
    if ! id "${username}" >/dev/null 2>&1; then
      adduser -D -h "${home_dir}" -s /bin/bash "${username}"
    fi
    mkdir -p "${home_dir}/.ssh"
    chmod 700 "${home_dir}/.ssh"
  done
fi

for logfile in /var/log/bastion_sessions/*.log; do
  [ -f "${logfile}" ] || continue
  chattr +a "${logfile}" 2>/dev/null || true
done

exec /usr/sbin/sshd -D -e
