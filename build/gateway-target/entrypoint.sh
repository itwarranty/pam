#!/bin/sh
# Mock target for gateway lab — OpenSSH server with mt_support account.
set -eu

apk add --no-cache openssh openssh-server-pam shadow sudo 2>/dev/null || true

if ! id mt_support >/dev/null 2>&1; then
  adduser -D -s /bin/bash mt_support
fi

mkdir -p /home/mt_support/.ssh
chmod 700 /home/mt_support/.ssh
if [ -f /etc/gateway-lab/authorized_keys ]; then
  cp /etc/gateway-lab/authorized_keys /home/mt_support/.ssh/authorized_keys
  chown -R mt_support:mt_support /home/mt_support/.ssh
  chmod 600 /home/mt_support/.ssh/authorized_keys
fi

ssh-keygen -A 2>/dev/null || true
printf '%s\n' \
  'PasswordAuthentication no' \
  'PermitRootLogin no' \
  'PubkeyAuthentication yes' \
  'AllowUsers mt_support' \
  >> /etc/ssh/sshd_config

exec /usr/sbin/sshd -D -e -p 22
