#!/bin/sh
# Provisioning операторов из read-only mount в локальный /home (rootless Podman + sshd privsep).
set -eu

OPERATORS_SRC="/etc/bastion/operators"
TARGETS_SRC="/etc/bastion/targets"
TARGETS_RUNTIME="/run/mt-bastion/targets-runtime"

# Gateway operators run as Unix users without access to root-only mounts; stage readable copies.
if [ -d "${TARGETS_SRC}" ]; then
  mkdir -p "${TARGETS_RUNTIME}"
  for src_dir in "${TARGETS_SRC}"/*; do
    [ -d "${src_dir}" ] || continue
    tid="$(basename "${src_dir}")"
    [ -f "${src_dir}/target.env" ] || continue
    mkdir -p "${TARGETS_RUNTIME}/${tid}"
    cp -f "${src_dir}/target.env" "${TARGETS_RUNTIME}/${tid}/target.env"
    chmod 0644 "${TARGETS_RUNTIME}/${tid}/target.env"
    if [ -f "${src_dir}/identity" ]; then
      cp -f "${src_dir}/identity" "${TARGETS_RUNTIME}/${tid}/identity"
      chmod 0600 "${TARGETS_RUNTIME}/${tid}/identity"
    fi
  done
  if [ -f "${TARGETS_SRC}/known_hosts" ]; then
    cp -f "${TARGETS_SRC}/known_hosts" "${TARGETS_RUNTIME}/known_hosts"
    chmod 0644 "${TARGETS_RUNTIME}/known_hosts"
  fi
fi

if [ -f /etc/bastion/command_denylist ]; then
  mkdir -p /run/mt-bastion
  cp -f /etc/bastion/command_denylist /run/mt-bastion/command_denylist
  chmod 0644 /run/mt-bastion/command_denylist
fi

for _sess_dir in /run/mt-bastion/sessions; do
  mkdir -p "${_sess_dir}"
  chmod 1777 "${_sess_dir}" 2>/dev/null || true
done

mkdir -p /run/mt-bastion
[ "${BASTION_GATEWAY_LAB_MODE:-0}" = "1" ] && echo 1 > /run/mt-bastion/lab_mode
[ "${BASTION_GATEWAY_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ] && echo 1 > /run/mt-bastion/policy_v2_enabled
[ "${BASTION_SHELL_COMMAND_POLICY_V2_ENABLED:-0}" = "1" ] && echo 1 > /run/mt-bastion/shell_policy_v2_enabled

if [ -f /run/mt-bastion/lab_mode ] && [ -d "${TARGETS_RUNTIME}" ] && command -v ssh-keyscan >/dev/null 2>&1; then
  : > "${TARGETS_RUNTIME}/known_hosts"
  for envf in "${TARGETS_RUNTIME}"/*/target.env; do
    [ -f "${envf}" ] || continue
    # shellcheck disable=SC1090
    . "${envf}"
    ssh-keyscan -p "${PORT}" "${HOST}" 2>/dev/null >> "${TARGETS_RUNTIME}/known_hosts" || true
  done
  chmod 0644 "${TARGETS_RUNTIME}/known_hosts" 2>/dev/null || true
fi

if [ -d "${OPERATORS_SRC}" ]; then
  for src_dir in "${OPERATORS_SRC}"/*; do
    [ -d "${src_dir}" ] || continue
    username="$(basename "${src_dir}")"
    home_dir="/home/${username}"

    mkdir -p "${home_dir}/.ssh"
    cp -f "${src_dir}/.ssh/authorized_keys" "${home_dir}/.ssh/authorized_keys" 2>/dev/null || true
    cp -f "${src_dir}/.google_authenticator" "${home_dir}/.google_authenticator" 2>/dev/null || true
    cp -f "${src_dir}/permit_open" "${home_dir}/permit_open" 2>/dev/null || true

    if [ -f "${home_dir}/permit_open" ] && [ -d "${TARGETS_RUNTIME}" ]; then
      rm -rf "${home_dir}/.bastion"
      mkdir -p "${home_dir}/.bastion/targets"
      if [ -f "${TARGETS_RUNTIME}/known_hosts" ]; then
        cp -f "${TARGETS_RUNTIME}/known_hosts" "${home_dir}/.bastion/known_hosts"
      fi
      while read -r hp || [ -n "${hp}" ]; do
        hp="$(printf '%s' "${hp}" | tr -d '\r')"
        [ -n "${hp}" ] || continue
        for envf in "${TARGETS_RUNTIME}"/*/target.env; do
          [ -f "${envf}" ] || continue
          # shellcheck disable=SC1090
          . "${envf}"
          if [ "${HOST}:${PORT}" = "${hp}" ]; then
            mkdir -p "${home_dir}/.bastion/targets/${ID}"
            cp -f "${TARGETS_RUNTIME}/${ID}/target.env" "${home_dir}/.bastion/targets/${ID}/target.env"
            if [ -f "${TARGETS_RUNTIME}/${ID}/identity" ]; then
              cp -f "${TARGETS_RUNTIME}/${ID}/identity" "${home_dir}/.bastion/targets/${ID}/identity"
            fi
          fi
        done
      done < "${home_dir}/permit_open"
    fi

    if ! id "${username}" >/dev/null 2>&1; then
      adduser -D -h "${home_dir}" -s /bin/bash "${username}"
    fi
    usermod -p '*' "${username}" 2>/dev/null || true
    chown -R "${username}:${username}" "${home_dir}"
    chmod 700 "${home_dir}" "${home_dir}/.ssh"
    chmod 600 "${home_dir}/.ssh/authorized_keys" "${home_dir}/.google_authenticator" "${home_dir}/permit_open" 2>/dev/null || true
    if [ -d "${home_dir}/.bastion/targets" ]; then
      find "${home_dir}/.bastion" -type f -exec chmod 600 {} \;
      chmod 700 "${home_dir}/.bastion" "${home_dir}/.bastion/targets" 2>/dev/null || true
    fi
  done

  # Отозванные операторы: удалить Unix-учётки, которых нет в mount
  for home_dir in /home/*; do
    [ -d "${home_dir}" ] || continue
    username="$(basename "${home_dir}")"
    [ -d "${OPERATORS_SRC}/${username}" ] && continue
    id "${username}" >/dev/null 2>&1 && deluser -r "${username}" 2>/dev/null || rm -rf "${home_dir}"
  done
fi

for logfile in /var/log/bastion_sessions/*.log; do
  [ -f "${logfile}" ] || continue
  chattr +a "${logfile}" 2>/dev/null || true
done

touch /var/log/bastion_sessions/bastion.syslog 2>/dev/null || true
chmod 0666 /var/log/bastion_sessions/bastion.syslog 2>/dev/null || true

exec /usr/sbin/sshd.pam -D -e
