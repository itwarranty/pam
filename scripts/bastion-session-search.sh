#!/usr/bin/env bash
# Query gateway/shell session events from sessions.jsonl (+ optional log grep).
set -euo pipefail

AUDIT_LOG_DIR="${AUDIT_LOG_DIR:-/var/log/bastion_sessions}"
JSONL="${AUDIT_LOG_DIR}/sessions.jsonl"
OPERATOR=""
TARGET_ID=""
TARGET_HOST=""
INCIDENT=""
SINCE=""
UNTIL=""
EVENT=""
GREP_PAT=""
JSON_OUT=false
LIMIT=100

usage() {
  cat <<'EOF'
Usage: bastion-session-search [options]

  --operator NAME       Filter by operator
  --target-id ID        Filter by target_id
  --target-host IP      Filter by target_host
  --incident INC-*      Filter incident_id prefix
  --since 7d|24h|ISO    Start window (default: all)
  --until ISO8601       End window
  --event NAME          gateway_start|gateway_end|moderator_watch_start
  --grep PATTERN        Search inside .log files (slow)
  --json                JSON lines output
  --limit N             Max results (default 100)
EOF
}

parse_since() {
  local spec="$1"
  case "${spec}" in
    *d) date -u -d "${spec%d} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${spec%d}"d +%Y-%m-%dT%H:%M:%SZ ;;
    *h) date -u -d "${spec%h} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${spec%h}"H +%Y-%m-%dT%H:%M:%SZ ;;
    *) printf '%s' "${spec}" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operator) OPERATOR="$2"; shift 2 ;;
    --target-id) TARGET_ID="$2"; shift 2 ;;
    --target-host) TARGET_HOST="$2"; shift 2 ;;
    --incident) INCIDENT="$2"; shift 2 ;;
    --since) SINCE="$2"; shift 2 ;;
    --until) UNTIL="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --grep) GREP_PAT="$2"; shift 2 ;;
    --json) JSON_OUT=true; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required on bastion host" >&2; exit 1; }
[[ -f "${JSONL}" ]] || { echo "No sessions.jsonl at ${JSONL}" >&2; exit 0; }

SINCE_ISO=""
[[ -n "${SINCE}" ]] && SINCE_ISO="$(parse_since "${SINCE}")"

filter='.'
[[ -n "${OPERATOR}" ]] && filter="${filter} | select(.operator==\"${OPERATOR}\")"
[[ -n "${TARGET_ID}" ]] && filter="${filter} | select(.target_id==\"${TARGET_ID}\")"
[[ -n "${TARGET_HOST}" ]] && filter="${filter} | select(.target_host==\"${TARGET_HOST}\")"
[[ -n "${INCIDENT}" ]] && filter="${filter} | select(.incident_id!=null and (.incident_id|startswith(\"${INCIDENT}\")))"
[[ -n "${EVENT}" ]] && filter="${filter} | select(.event==\"${EVENT}\")"
[[ -n "${SINCE_ISO}" ]] && filter="${filter} | select(.ts >= \"${SINCE_ISO}\")"
[[ -n "${UNTIL}" ]] && filter="${filter} | select(.ts <= \"${UNTIL}\")"

if [[ "${JSON_OUT}" == true ]]; then
  jq -c "${filter}" "${JSONL}" | head -n "${LIMIT}"
else
  printf '%-22s %-12s %-16s %-18s %s\n' "TS" "EVENT" "OPERATOR" "TARGET" "SESSION_ID"
  jq -r "${filter} | [.ts, .event, (.operator//\"-\"), (.target_id//\"-\"), (.session_id//\"-\")] | @tsv" "${JSONL}" \
    | head -n "${LIMIT}" \
    | while IFS=$'\t' read -r ts ev op tid sid; do
        printf '%-22s %-12s %-16s %-18s %s\n' "${ts}" "${ev}" "${op}" "${tid}" "${sid}"
      done
fi

if [[ -n "${GREP_PAT}" ]]; then
  echo "--- log grep (${GREP_PAT}) ---" >&2
  find "${AUDIT_LOG_DIR}" -name '*.log' -type f 2>/dev/null | head -200 | while read -r f; do
    grep -l "${GREP_PAT}" "${f}" 2>/dev/null || true
  done | head -n "${LIMIT}"
fi
