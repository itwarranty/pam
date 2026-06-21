#!/bin/sh
# Guest Wi‑Fi lab router: NAT/forward между сегментами + client isolation guest→corp.
set -eu

GUEST_IF="${GUEST_IF:-eth0}"
CORP_IF="${CORP_IF:-eth1}"
DMZ_IF="${DMZ_IF:-eth2}"

GUEST_GW="${GUEST_GW:-10.1.13.1}"
CORP_GW="${CORP_GW:-10.0.1.1}"
DMZ_GW="${DMZ_GW:-10.0.2.1}"

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Адреса на интерфейсах (Podman может уже назначить — добавляем gw при необходимости)
ip addr show dev "${GUEST_IF}" | grep -q "${GUEST_GW}" || ip addr add "${GUEST_GW}/24" dev "${GUEST_IF}"
ip addr show dev "${CORP_IF}" | grep -q "${CORP_GW}" || ip addr add "${CORP_GW}/24" dev "${CORP_IF}"
ip addr show dev "${DMZ_IF}" | grep -q "${DMZ_GW}" || ip addr add "${DMZ_GW}/24" dev "${DMZ_IF}"

ip link set "${GUEST_IF}" up
ip link set "${CORP_IF}" up
ip link set "${DMZ_IF}" up

iptables -P FORWARD DROP

# Guest → Internet (через NAT хоста): разрешаем forward guest→corp/dmz только по политике ниже
iptables -t nat -A POSTROUTING -s 10.1.13.0/24 -o "${CORP_IF}" -j MASQUERADE 2>/dev/null || true

# Guest НЕ видит corp internal (client isolation / AP isolation)
iptables -A FORWARD -i "${GUEST_IF}" -o "${CORP_IF}" -j DROP
iptables -A FORWARD -i "${CORP_IF}" -o "${GUEST_IF}" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Guest → DMZ (bastion SSH) — типичный вход инженера с guest Wi‑Fi
iptables -A FORWARD -i "${GUEST_IF}" -o "${DMZ_IF}" -p tcp --dport 2222 -j ACCEPT
iptables -A FORWARD -i "${DMZ_IF}" -o "${GUEST_IF}" -m state --state ESTABLISHED,RELATED -j ACCEPT

# DMZ (bastion) → corp targets — контролируемый jump/gateway
iptables -A FORWARD -i "${DMZ_IF}" -o "${CORP_IF}" -j ACCEPT
iptables -A FORWARD -i "${CORP_IF}" -o "${DMZ_IF}" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Guest ICMP к шлюзу
iptables -A INPUT -i "${GUEST_IF}" -p icmp -j ACCEPT

printf '[guest-wifi-router] up guest=%s corp=%s dmz=%s\n' "${GUEST_GW}" "${CORP_GW}" "${DMZ_GW}"
exec sleep infinity
