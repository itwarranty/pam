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
      ssh-keygen -t ed25519 -f "lab/keys/${u}.lab" -N "" -C "${u}@example.com"
    fi
  done
  for u in engineer-jump engineer-shell engineer-audit breakglass-lab gateway-lab; do
    if [[ ! -f "lab/keys/${u}.lab" ]]; then
      echo "[dev-up] Generating lab/keys/${u}.lab ..."
      ssh-keygen -t ed25519 -f "lab/keys/${u}.lab" -N "" -C "${u}@example.com"
    fi
  done
}

ensure_fido_lab_keys() {
  [[ "${PAM_FIDO_LAB:-0}" == "1" ]] || return 0
  if [[ -f lab/keys/engineer-fido.lab ]]; then
    echo "[dev-up] FIDO lab key engineer-fido.lab already present"
    return 0
  fi
  echo "[dev-up] Generating FIDO sk key lab/keys/engineer-fido.lab (verify-required) ..."
  if ssh-keygen -t ed25519-sk -O verify-required -f lab/keys/engineer-fido.lab -N "" -C "engineer-fido@example.com" 2>/dev/null; then
    echo "[dev-up] FIDO lab key OK — enable pam_fido_lab_enabled for deploy"
  else
    echo "[dev-up] SKIP FIDO key: no sk/FIDO support on this host."
    echo "[dev-up] See docs/FIDO-Onboarding.md — use Mac Touch ID or YubiKey manually."
  fi
}

INSTANCE="${LIMA_INSTANCE_NAME:-pam-prod}"

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
  if limactl shell "${INSTANCE}" -- test -f /tmp/trusted_upstream_packages/pam_image.tar 2>/dev/null; then
    echo "[dev-up] Image already in Lima VM"
    return
  fi
  if [[ -f /tmp/trusted_upstream_packages/pam_image.tar ]]; then
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

print_lab_summary() {
  echo ""
  echo "=== Lab operators (SSH PAM) ==="
  printf '%-18s %-8s  %s\n' "OPERATOR" "ACCESS" "HOW TO CONNECT"
  printf '%-18s %-8s  %s\n' "----------" "------" "--------------"
  python3 - "${ROOT}" <<'PY'
import json, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1])
script = root / "scripts" / "lib" / "parse-lab-operators.py"
ops = json.loads(subprocess.check_output([sys.executable, str(script), str(root / "group_vars" / "dev")], text=True))
hints = {
    "jump": "ProxyJump (-J) — NOT direct ssh; ./scripts/pam doctor NAME",
    "gateway": "ssh -p 2222 -i lab/keys/NAME.lab NAME@127.0.0.1",
    "shell": "ssh -p 2222 -i lab/keys/NAME.lab NAME@127.0.0.1",
    "audit": "ssh -p 2222 -i lab/keys/NAME.lab NAME@127.0.0.1",
}
for o in sorted(ops, key=lambda x: x["name"]):
    acc = o.get("access", "jump")
    hint = hints.get(acc, "ssh -p 2222 -i lab/keys/NAME.lab NAME@127.0.0.1").replace("NAME", o["name"])
    print(f"{o['name']:<18} {acc:<8}  {hint}")
PY
  echo ""
  echo "TOTP: ./scripts/pam doctor <operator>  (live 6-digit code)"
  echo "Pre-login banner on the gateway reminds: jump → use -J"
  echo ""
}

ensure_lab_keys
ensure_fido_lab_keys
ensure_lima
ensure_image

ansible-galaxy collection install -r requirements.yml

EXTRA_ARGS=()
if [[ "${PAM_FIDO_LAB:-0}" == "1" ]]; then
  EXTRA_ARGS+=(-e pam_fido_lab_enabled=true)
fi

echo "[dev-up] Deploying (dev operators from group_vars/dev/) ..."
ansible-playbook -i inventory/local-lima.yml site.yml "${EXTRA_ARGS[@]}"

print_lab_summary
