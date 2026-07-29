#!/usr/bin/env bash
# Поднять лёгкий стенд guest Wi‑Fi + corp internal + gateway DMZ (Podman, один Linux-хост).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/topology.env"

if ! command -v podman >/dev/null 2>&1; then
  printf 'ERROR: podman required (Rocky/RHEL/Fedora: dnf install podman)\n' >&2
  exit 1
fi

net_create() {
  local name="$1" cidr="$2"
  if podman network exists "${name}" 2>/dev/null; then
    printf '[up] network %s exists\n' "${name}"
  else
    podman network create --subnet "${cidr}" "${name}"
  fi
}

NET_GUEST="${LAB_PREFIX}-guest"
NET_CORP="${LAB_PREFIX}-corp"
NET_DMZ="${LAB_PREFIX}-dmz"

net_create "${NET_GUEST}" "${GUEST_CIDR}"
net_create "${NET_CORP}" "${CORP_CIDR}"
net_create "${NET_DMZ}" "${DMZ_CIDR}"

podman rm -f "${LAB_PREFIX}-router" "${LAB_PREFIX}-guest-pc" "${LAB_PREFIX}-target" "${LAB_PREFIX}-gateway-mock" 2>/dev/null || true

printf '[up] router (iptables isolation)\n'
ROUTER_ENTRY="/tmp/${LAB_PREFIX}-router-entrypoint.sh"
cp "${ROOT}/router/entrypoint.sh" "${ROUTER_ENTRY}"
chmod +x "${ROUTER_ENTRY}"
podman run -d --name "${LAB_PREFIX}-router" \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --sysctl net.ipv4.ip_forward=1 \
  --network "${NET_GUEST}" --network "${NET_CORP}" --network "${NET_DMZ}" \
  -e GUEST_GW="${GUEST_GW}" -e CORP_GW="${CORP_GW}" -e DMZ_GW="${DMZ_GW}" \
  -v "${ROUTER_ENTRY}:/entrypoint.sh:ro" \
  --entrypoint /bin/sh \
  "${ROUTER_IMAGE}" /entrypoint.sh

printf '[up] guest workstation %s\n' "${GUEST_CLIENT_IP}"
podman run -d --name "${LAB_PREFIX}-guest-pc" \
  --network "${NET_GUEST}:ip=${GUEST_CLIENT_IP}" \
  "${CLIENT_IMAGE}" sleep infinity
podman exec "${LAB_PREFIX}-guest-pc" sh -c 'apk add --no-cache openssh-client iputils bind-tools curl >/dev/null 2>&1 || true'

printf '[up] internal target %s (ssh mock)\n' "${CORP_TARGET_IP}"
podman run -d --name "${LAB_PREFIX}-target" \
  --network "${NET_CORP}:ip=${CORP_TARGET_IP}" \
  "${CLIENT_IMAGE}" sleep infinity
podman exec "${LAB_PREFIX}-target" sh -c 'apk add --no-cache openssh openssh-client iputils >/dev/null 2>&1 && ssh-keygen -A >/dev/null 2>&1 && echo "root:lab" | chpasswd && /usr/sbin/sshd'

printf '[up] gateway mock %s:2222 (placeholder; attach ssh_pam separately)\n' "${DMZ_PAM_IP}"
podman run -d --name "${LAB_PREFIX}-gateway-mock" \
  --network "${NET_DMZ}:ip=${DMZ_PAM_IP}" \
  -p 12222:2222 \
  "${CLIENT_IMAGE}" sleep infinity
podman exec "${LAB_PREFIX}-gateway-mock" sh -c 'apk add --no-cache openssh iputils >/dev/null 2>&1 && ssh-keygen -A >/dev/null 2>&1 && echo "gateway-mock:lab" | chpasswd && printf "Port 2222\nPermitRootLogin yes\nPasswordAuthentication yes\n" >> /etc/ssh/sshd_config && /usr/sbin/sshd'

# Default route на guest-pc → lab router
podman exec "${LAB_PREFIX}-guest-pc" ip route replace default via "${GUEST_GW}"

cat <<EOF

=== Guest Wi‑Fi lab UP ===
Guest PC:     podman exec -it ${LAB_PREFIX}-guest-pc sh
Gateway mock: ssh -p 12222 gateway-mock@127.0.0.1  (password: lab, port 2222 inside)
Target (corp): ${CORP_TARGET_IP} — reachable only from DMZ, NOT from guest

Verify:  ${ROOT}/scripts/verify.sh
Attach real SSH PAM container to ${NET_DMZ} — see README.md

EOF
