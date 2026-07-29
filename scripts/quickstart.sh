#!/usr/bin/env bash
# ITWarranty SSH PAM — first successful lab stand in one command.
# Requires: macOS/Linux with Lima (or existing Rocky 9 host), Podman preferred.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

log() { printf '[quickstart] %s\n' "$*"; }
die() { printf '[quickstart] ERROR: %s\n' "$*" >&2; exit 1; }

check_prereqs() {
  local missing=()
  command -v ansible-playbook >/dev/null 2>&1 || missing+=("ansible")
  command -v limactl >/dev/null 2>&1 || missing+=("lima")
  if [[ ${#missing[@]} -gt 0 ]]; then
    log "Missing tools: ${missing[*]}"
    log "macOS: brew install lima podman ansible"
    log "Or deploy on an existing Rocky 9 host: see README Prod deploy"
    if [[ " ${missing[*]} " == *" lima "* ]] && [[ "${QUICKSTART_ALLOW_HOST:-0}" != "1" ]]; then
      die "lima required for local quickstart (or set QUICKSTART_ALLOW_HOST=1 with inventory)"
    fi
  fi
}

print_next() {
  cat <<EOF

=== ITWarranty SSH PAM is ready (lab) ===

Check an operator:
  ./scripts/pam doctor gateway-lab
  ./scripts/pam doctor engineer-jump

Compliance:
  limactl shell pam-prod -- sudo bash -c 'cd ${ROOT} && ./scripts/pam verify'

Sessions (on the gateway host):
  ./scripts/pam sessions list

Docs:
  docs/Runbooks.md
  docs/CSO-Demo-Runbook.md

Need help deploying at a customer site?
  https://github.com/itwarranty
EOF
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Usage: ./scripts/quickstart.sh

Builds/loads the Air Gap image, starts Lima Rocky 9, deploys lab operators.

Same as: ./scripts/dev-up.sh
Also:    ./scripts/pam up
EOF
    exit 0
  fi

  check_prereqs
  log "Starting lab stand (this can take 10–20 min on first run) ..."
  chmod +x "${ROOT}/scripts/"*.sh "${ROOT}/scripts/pam" 2>/dev/null || true
  bash "${ROOT}/scripts/dev-up.sh"
  print_next
}

main "$@"
