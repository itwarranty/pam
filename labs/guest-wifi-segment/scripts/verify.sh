#!/usr/bin/env bash
# Проверка изоляции guest→corp и доступности gateway DMZ с guest workstation.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "${ROOT}/topology.env"

GUEST="${LAB_PREFIX}-guest-pc"
PASS=0
FAIL=0

check() {
  local name="$1" rc="$2"
  if [[ "${rc}" -eq 0 ]]; then
    printf '[PASS] %s\n' "${name}"
    PASS=$((PASS + 1))
  else
    printf '[FAIL] %s\n' "${name}" >&2
    FAIL=$((FAIL + 1))
  fi
}

podman container exists "${GUEST}" >/dev/null 2>&1 || {
  printf 'Lab not running. Run: %s/scripts/up.sh\n' "${ROOT}" >&2
  exit 1
}

# Guest → gateway (как 10.1.13.1 у вас)
podman exec "${GUEST}" ping -c 1 -W 2 "${GUEST_GW}" >/dev/null 2>&1
check "guest → guest gateway (${GUEST_GW})" $?

# Guest → corp target MUST fail (AP/client isolation)
if podman exec "${GUEST}" ping -c 1 -W 2 "${CORP_TARGET_IP}" >/dev/null 2>&1; then
  check "guest → corp target BLOCKED (${CORP_TARGET_IP})" 1
else
  check "guest → corp target BLOCKED (${CORP_TARGET_IP})" 0
fi

# Guest → DMZ gateway SSH (via router forward :2222 — mock listens on 22 inside, map test via nc)
if podman exec "${GUEST}" sh -c "nc -z -w 2 ${DMZ_PAM_IP} 2222" >/dev/null 2>&1; then
  check "guest → dmz gateway :2222 (${DMZ_PAM_IP})" 0
else
  check "guest → dmz gateway :2222 (${DMZ_PAM_IP})" 1
fi

# DMZ → corp (path for real gateway sessions)
podman exec "${LAB_PREFIX}-gateway-mock" ping -c 1 -W 2 "${CORP_TARGET_IP}" >/dev/null 2>&1
check "dmz gateway → corp target (${CORP_TARGET_IP})" $?

printf '\n=== Summary: %s passed, %s failed ===\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]]
