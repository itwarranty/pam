#!/usr/bin/env bash
# Dev: Lima Rocky 9 + lab keys + deploy (без Vault, без prod-операторов)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

ensure_lab_keys() {
  mkdir -p lab/keys
  for u in gateway-target-support; do
    if [[ ! -f "lab/keys/${u}.lab" ]]; then
      echo "[dev-up] Generating lab/keys/${u}.lab (target SA key) ..."
      ssh-keygen -t ed25519 -f "lab/keys/${u}.lab" -N "" -C "${u}@mtglobal.team"
    fi
  done
  for u in engineer-jump engineer-shell engineer-audit breakglass-lab gateway-lab; do
    if [[ ! -f "lab/keys/${u}.lab" ]]; then
      echo "[dev-up] Generating lab/keys/${u}.lab ..."
      ssh-keygen -t ed25519 -f "lab/keys/${u}.lab" -N "" -C "${u}@mtglobal.team"
    fi
  done
}

ensure_fido_lab_keys() {
  [[ "${BASTION_FIDO_LAB:-0}" == "1" ]] || return 0
  if [[ -f lab/keys/engineer-fido.lab ]]; then
    echo "[dev-up] FIDO lab key engineer-fido.lab already present"
    return 0
  fi
  echo "[dev-up] Generating FIDO sk key lab/keys/engineer-fido.lab (verify-required) ..."
  if ssh-keygen -t ed25519-sk -O verify-required -f lab/keys/engineer-fido.lab -N "" -C "engineer-fido@mtglobal.team" 2>/dev/null; then
    echo "[dev-up] FIDO lab key OK — enable bastion_fido_lab_enabled for deploy"
  else
    echo "[dev-up] SKIP FIDO key: no sk/FIDO support on this host."
    echo "[dev-up] See docs/MT-Bastion-FIDO-Onboarding.md — use Mac Touch ID or YubiKey manually."
  fi
}

INSTANCE="${LIMA_INSTANCE_NAME:-mt-bastion-prod}"

ensure_lima() {
  chmod +x tests/*.sh 2>/dev/null || true
  if limactl list "${INSTANCE}" 2>/dev/null | grep -q "Running"; then
    echo "[dev-up] Lima VM already running"
    return
  fi
  echo "[dev-up] Starting Lima VM (Rocky 9 x86_64 — первый запуск может занять 10–20 мин) ..."
  ./tests/start-lima.sh
}

ensure_image() {
  if limactl shell "${INSTANCE}" -- test -f /tmp/trusted_upstream_packages/mt_bastion_image.tar 2>/dev/null; then
    echo "[dev-up] Image already in Lima VM"
    return
  fi
  if [[ -f /tmp/trusted_upstream_packages/mt_bastion_image.tar ]]; then
    echo "[dev-up] Syncing image to Lima ..."
    ./tests/sync-artifacts.sh
    return
  fi
  if command -v podman >/dev/null 2>&1; then
    echo "[dev-up] Building Air Gap image on host ..."
    ./trusted_download.sh
    ./tests/sync-artifacts.sh
    return
  fi
  echo "[dev-up] Host podman not found — building inside Lima VM ..."
  limactl shell "${INSTANCE}" -- bash -c "cd '${ROOT}' && ./trusted_download.sh"
}

ensure_lab_keys
ensure_fido_lab_keys
ensure_lima
ensure_image

ansible-galaxy collection install -r requirements.yml

EXTRA_ARGS=()
if [[ "${BASTION_FIDO_LAB:-0}" == "1" ]]; then
  EXTRA_ARGS+=(-e bastion_fido_lab_enabled=true)
fi

echo "[dev-up] Deploying (dev operators from group_vars/dev/) ..."
ansible-playbook -i inventory/local-lima.yml site.yml "${EXTRA_ARGS[@]}"

echo ""
echo "[dev-up] SSH bastion (порт 2222, после деплоя):"
echo "  ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1"
echo "  ssh -p 2222 -i lab/keys/engineer-shell.lab engineer-shell@127.0.0.1"
echo "  ssh -p 2222 -i lab/keys/engineer-audit.lab engineer-audit@127.0.0.1"
echo "  ssh -p 2222 -i lab/keys/breakglass-lab.lab breakglass-lab@127.0.0.1"
echo "  ssh -p 2222 -i lab/keys/gateway-lab.lab gateway-lab@127.0.0.1"
if [[ "${BASTION_FIDO_LAB:-0}" == "1" ]] && [[ -f lab/keys/engineer-fido.lab ]]; then
  echo "  ssh -p 2222 -i lab/keys/engineer-fido.lab engineer-fido@127.0.0.1  # FIDO-sk + TOTP"
fi
echo "TOTP: см. otpauth URI в group_vars/dev/lab.yml (engineer-fido — fido_lab.yml)"
