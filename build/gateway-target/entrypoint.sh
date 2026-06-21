#!/bin/sh
# Mock target for gateway lab — OpenSSH server with bastion_support account.
set -eu

apk add --no-cache openssh openssh-server-pam shadow sudo 2>/dev/null || true

if ! id bastion_support >/dev/null 2>&1; then
  adduser -D -s /bin/sh bastion_support
fi
usermod -p '*' bastion_support 2>/dev/null || true
passwd -u bastion_support 2>/dev/null || true

mkdir -p /home/bastion_support/.ssh
chmod 700 /home/bastion_support/.ssh
if [ -f /etc/gateway-lab/authorized_keys ]; then
  cp /etc/gateway-lab/authorized_keys /home/bastion_support/.ssh/authorized_keys
  chown -R bastion_support:bastion_support /home/bastion_support/.ssh
  chmod 600 /home/bastion_support/.ssh/authorized_keys
fi

ssh-keygen -A 2>/dev/null || true
printf '%s\n' \
  'PasswordAuthentication no' \
  'PermitRootLogin no' \
  'PubkeyAuthentication yes' \
  'AllowUsers bastion_support' \
  >> /etc/ssh/sshd_config

exec /usr/sbin/sshd -D -e -p 22
