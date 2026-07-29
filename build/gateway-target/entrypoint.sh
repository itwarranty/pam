#!/bin/sh
# Mock target for gateway lab — OpenSSH server with pam_support account.
set -eu

apk add --no-cache openssh openssh-server-pam shadow sudo 2>/dev/null || true

if ! id pam_support >/dev/null 2>&1; then
  adduser -D -s /bin/sh pam_support
fi
usermod -p '*' pam_support 2>/dev/null || true
passwd -u pam_support 2>/dev/null || true

mkdir -p /home/pam_support/.ssh
chmod 700 /home/pam_support/.ssh
if [ -f /etc/gateway-lab/authorized_keys ]; then
  cp /etc/gateway-lab/authorized_keys /home/pam_support/.ssh/authorized_keys
  chown -R pam_support:pam_support /home/pam_support/.ssh
  chmod 600 /home/pam_support/.ssh/authorized_keys
fi

ssh-keygen -A 2>/dev/null || true
printf '%s\n' \
  'PasswordAuthentication no' \
  'PermitRootLogin no' \
  'PubkeyAuthentication yes' \
  'AllowUsers pam_support' \
  >> /etc/ssh/sshd_config

exec /usr/sbin/sshd -D -e -p 22
