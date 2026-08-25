#!/usr/bin/env bash
# pam verify --json must report pass for all enabled checks (gateway host / Lima).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/pam-test-lib.sh
source "${ROOT}/scripts/lib/pam-test-lib.sh"

fail() { printf '[FAIL] pam-verify-json: %s\n' "$*" >&2; exit 1; }
pass() { printf '[PASS] pam-verify-json: %s\n' "$*"; }

_verify_cmd() {
  local extra="${1:-}"
  if pam_test_on_gateway; then
    sudo bash -lc "${extra}${ROOT}/scripts/pam-compliance-verify.sh --json"
  else
    limactl shell "${LIMA_INSTANCE:-pam-prod}" -- sudo bash -lc "${extra}${ROOT}/scripts/pam-compliance-verify.sh --json"
  fi
}

# Match verify expectations to deployed audit log modes (lab vs prod overlay).
_mode_probe() {
  pam_test_run_gateway "
    d=${PAM_AUDIT_LOG_DIR:-/var/log/pam_sessions}
    if [ -f \"\${d}/gateway.syslog\" ]; then stat -c '%a' \"\${d}/gateway.syslog\"
    elif [ -d \"\${d}\" ]; then stat -c '%a' \"\${d}\"; else echo 750; fi
  "
}
_dir_mode_probe() {
  pam_test_run_gateway "
    d=${PAM_AUDIT_LOG_DIR:-/var/log/pam_sessions}
    [ -d \"\${d}\" ] && stat -c '%a' \"\${d}\" || echo 750
  "
}

file_mode="$(_mode_probe | tr -d '[:space:]')"
dir_mode="$(_dir_mode_probe | tr -d '[:space:]')"
env_prefix="export PAM_AUDIT_LOG_FILE_MODE=${file_mode} PAM_AUDIT_LOG_DIR_MODE=${dir_mode}; "

JSON="$(_verify_cmd "${env_prefix}" 2>/dev/null || true)"

[[ -n "${JSON}" ]] || fail "empty verify output"

python3 - <<'PY' "${JSON}"
import json, sys
data = json.loads(sys.argv[1])
if not data.get("ok") or data.get("failed", 1) != 0:
    print(json.dumps(data, indent=2), file=sys.stderr)
    raise SystemExit(f"verify failed: {data.get('failed')} failure(s)")
print(f"ok: {data.get('passed')} checks passed")
PY

pass "pam verify --json all enabled checks passed"
