#!/bin/sh
# Provisioning операторов из read-only mount в локальный /home (rootless Podman + sshd privsep).
set -eu

OPERATORS_SRC="/etc/bastion/operators"

if [ -d "${OPERATORS_SRC}" ]; then
  for src_dir in "${OPERATORS_SRC}"/*; do
    [ -d "${src_dir}" ] || continue
    username="$(basename "${src_dir}")"
    home_dir="/home/${username}"

    mkdir -p "${home_dir}/.ssh"
    cp -f "${src_dir}/.ssh/authorized_keys" "${home_dir}/.ssh/authorized_keys" 2>/dev/null || true
    cp -f "${src_dir}/.google_authenticator" "${home_dir}/.google_authenticator" 2>/dev/null || true

    if ! id "${username}" >/dev/null 2>&1; then
      adduser -D -h "${home_dir}" -s /bin/bash "${username}"
    fi
    usermod -p '*' "${username}" 2>/dev/null || true
    chown -R "${username}:${username}" "${home_dir}"
    chmod 700 "${home_dir}" "${home_dir}/.ssh"
    chmod 600 "${home_dir}/.ssh/authorized_keys" "${home_dir}/.google_authenticator" 2>/dev/null || true
  done
fi

for logfile in /var/log/bastion_sessions/*.log; do
  [ -f "${logfile}" ] || continue
  chattr +a "${logfile}" 2>/dev/null || true
done

exec /usr/sbin/sshd.pam -D -e
