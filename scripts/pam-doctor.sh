#!/usr/bin/env bash
# SSH PAM — pre-flight checks for lab operators (local workstation).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

NAME="${1:-}"
PAM_HOST="${PAM_HOST:-127.0.0.1}"
PAM_PORT="${PAM_PORT:-2222}"
KEYS_DIR="${PAM_KEYS_DIR:-${ROOT}/lab/keys}"

usage() {
  cat <<EOF
Usage: pam-doctor.sh <operator> [operator2 ...]
       pam-doctor.sh --list

Lab operators from group_vars/dev/*.yml. Examples:
  ./scripts/pam-doctor.sh engineer-jump
  ./scripts/pam-doctor.sh gateway-lab
EOF
}

list_operators() {
  python3 "${ROOT}/scripts/lib/parse-lab-operators.py" "${ROOT}/group_vars/dev" \
    | python3 -c "import json,sys; [print(o['name']) for o in json.load(sys.stdin)]"
}

totp_now() {
  local secret="$1"
  if command -v oathtool >/dev/null 2>&1; then
    oathtool --totp -b "${secret}" 2>/dev/null || echo "(oathtool failed)"
  else
    echo "(install oathtool: brew install oath-toolkit)"
  fi
}

check_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z "${PAM_HOST}" "${PAM_PORT}" 2>/dev/null && echo "open" || echo "closed"
  else
    echo "unknown (nc missing)"
  fi
}

describe_access() {
  local access="$1"
  local name="$2"
  local permits="$3"
  case "${access}" in
    jump)
      printf '  Role jump: interactive shell on the gateway is DISABLED.\n'
      printf '  Use ProxyJump (-J), not: ssh %s@gateway\n' "${name}"
      if [[ -n "${permits}" ]]; then
        local first target host port
        first="$(printf '%s' "${permits}" | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p[0] if p else "")')"
        [[ -n "${first}" ]] || return 0
        host="${first%%:*}"
        port="${first##*:}"
        target="${host}"
        printf '\n  Example:\n'
        printf '    ssh -J %s@%s:%s user@%s\n' "${name}" "${PAM_HOST}" "${PAM_PORT}" "${host}"
      fi
      ;;
    gateway)
      printf '  Role gateway: interactive SSH to gateway → target menu / session.\n'
      printf '    ssh -p %s -i %s/%s.lab %s@%s\n' "${PAM_PORT}" "${KEYS_DIR}" "${name}" "${name}" "${PAM_HOST}"
      ;;
    shell|audit)
      printf '  Role %s: direct SSH to gateway (ForceCommand wrapper).\n' "${access}"
      printf '    ssh -p %s -i %s/%s.lab %s@%s\n' "${PAM_PORT}" "${KEYS_DIR}" "${name}" "${name}" "${PAM_HOST}"
      ;;
    *)
      printf '  Role %s\n' "${access}"
      ;;
  esac
}

doctor_one() {
  local name="$1"
  local key access secret permits port_status totp
  local py_out

  py_out="$(python3 - "${name}" "${ROOT}" <<'PY'
import json, subprocess, sys
from pathlib import Path

name = sys.argv[1]
root = Path(sys.argv[2])
script = root / "scripts" / "lib" / "parse-lab-operators.py"
raw = subprocess.check_output([sys.executable, str(script), str(root / "group_vars" / "dev")], text=True)
ops = {o["name"]: o for o in json.loads(raw)}
op = ops.get(name)
if not op:
    print(json.dumps({"error": "unknown", "known": sorted(ops.keys())}))
else:
    print(json.dumps(op))
PY
)"

  if python3 -c "import json,sys; d=json.loads(sys.argv[1]); exit(1 if 'error' in d else 0)" "${py_out}"; then
    :
  else
    printf '[FAIL] Unknown lab operator: %s\n' "${name}" >&2
    python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('Known:', ', '.join(d.get('known',[])))" "${py_out}" >&2
    return 1
  fi

  access="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('access','jump'))" <<<"${py_out}")"
  secret="$(python3 -c "import json,sys; print(json.load(sys.stdin).get('mfa_secret',''))" <<<"${py_out}")"
  permits="$(python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin).get('permit_open',[])))" <<<"${py_out}")"

  key="${KEYS_DIR}/${name}.lab"
  port_status="$(check_port)"
  totp="$(totp_now "${secret}")"

  printf '=== PAM doctor: %s ===\n\n' "${name}"

  if [[ -f "${key}" ]]; then
    printf '[PASS] Private key: %s\n' "${key}"
  else
    printf '[FAIL] Private key missing: %s (run ./scripts/dev-up.sh)\n' "${key}"
  fi

  printf '[%s] Gateway %s:%s — %s\n' \
    "$( [[ "${port_status}" == open ]] && echo PASS || echo WARN )" \
    "${PAM_HOST}" "${PAM_PORT}" "${port_status}"

  if [[ -n "${secret}" ]]; then
    printf '[INFO] TOTP now (%s): %s  (30s window — enter immediately at MFA prompt)\n' "${name}" "${totp}"
    printf '[INFO] otpauth secret ends: ...%s\n' "${secret: -8}"
  else
    printf '[WARN] No mfa_secret in dev YAML for %s\n' "${name}"
  fi

  printf '\n'
  describe_access "${access}" "${name}" "${permits}"
  printf '\n'
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi
  if [[ "${1:-}" == "--list" ]]; then
    list_operators
    exit 0
  fi
  if [[ -z "${NAME}" ]]; then
    usage >&2
    exit 1
  fi
  local failed=0
  for n in "$@"; do
    doctor_one "${n}" || failed=1
    printf '\n'
  done
  exit "${failed}"
}

main "$@"
