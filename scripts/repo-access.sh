#!/usr/bin/env bash
# Read-only доступ к gateway через GitHub (не deploy keys).
# Инженер использует свой SSH-ключ в https://github.com/settings/ssh-keys
# Вы выдаёте/отзываете доступ к репозиторию (permission=pull).
#
#   ./scripts/repo-access.sh grant ivanov    # Read на repo (team gateway-readers)
#   ./scripts/repo-access.sh revoke ivanov
#   ./scripts/repo-access.sh list
#
# Вне org (outside collaborator):
#   ./scripts/repo-access.sh grant ivanov --collaborator
#
# Переменные:
#   GITHUB_REPO=itwarranty/pam
#   READERS_TEAM=gateway-readers

set -euo pipefail

GITHUB_REPO="${GITHUB_REPO:-itwarranty/pam}"
READERS_TEAM="${READERS_TEAM:-gateway-readers}"
OWNER="${GITHUB_REPO%%/*}"
REPO="${GITHUB_REPO#*/}"

log() { printf '[repo-access] %s\n' "$*"; }
die() { printf '[repo-access] ERROR: %s\n' "$*" >&2; exit 1; }

require_gh() {
  command -v gh >/dev/null 2>&1 || die "Нужен gh CLI: https://cli.github.com/"
  gh auth status >/dev/null 2>&1 || die "gh не авторизован: gh auth login"
}

sanitize_user() {
  local user="$1"
  [[ "${user}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$ ]] \
    || die "Некорректный GitHub username: ${user}"
}

user_exists() {
  gh api "users/${1}" --jq .login >/dev/null 2>&1
}

org_member() {
  gh api "orgs/${OWNER}/members/${1}" --jq .login >/dev/null 2>&1
}

team_exists() {
  gh api "orgs/${OWNER}/teams/${READERS_TEAM}" --jq .slug >/dev/null 2>&1
}

ensure_readers_team() {
  if team_exists; then
    return 0
  fi
  log "Создание team ${READERS_TEAM} (Read на ${GITHUB_REPO})"
  gh api "orgs/${OWNER}/teams" \
    -X POST \
    -f name="${READERS_TEAM}" \
    -f privacy="closed" \
    --jq '{slug, name}' >/dev/null
  gh api "orgs/${OWNER}/teams/${READERS_TEAM}/repos/${OWNER}/${REPO}" \
    -X PUT \
    -f permission="pull" >/dev/null
}

cmd_grant_team() {
  local user="$1"
  ensure_readers_team
  if ! org_member "${user}"; then
    die "${user} не в org ${OWNER}. Пригласите: https://github.com/orgs/${OWNER}/people — или используйте --collaborator"
  fi
  log "Добавление ${user} в team ${READERS_TEAM} (Read)"
  gh api "orgs/${OWNER}/teams/${READERS_TEAM}/memberships/${user}" \
    -X PUT \
    -f role="member" \
    --jq '{state, role}'
  print_engineer_instructions "${user}"
}

cmd_grant_collaborator() {
  local user="$1"
  if ! user_exists "${user}"; then
    die "GitHub user не найден: ${user}"
  fi
  log "Outside collaborator Read: ${user} → ${GITHUB_REPO}"
  gh api "repos/${OWNER}/${REPO}/collaborators/${user}" \
    -X PUT \
    -f permission="pull" \
    --jq '{invitation, permissions}'
  print_engineer_instructions "${user}"
}

print_engineer_instructions() {
  local user="$1"
  cat <<EOF

--- Инструкция для ${user} ---

1. SSH-ключ (если ещё нет):
   ssh-keygen -t ed25519 -C "${user}@example.com"
   → добавить ~/.ssh/id_ed25519.pub в https://github.com/settings/ssh-keys

2. Clone:
   git clone git@github.com:${GITHUB_REPO}.git

EOF
}

cmd_revoke_team() {
  local user="$1"
  if ! team_exists; then
    die "Team ${READERS_TEAM} не существует"
  fi
  log "Удаление ${user} из team ${READERS_TEAM}"
  gh api "orgs/${OWNER}/teams/${READERS_TEAM}/memberships/${user}" -X DELETE
  log "Доступ Read через team отозван."
}

cmd_revoke_collaborator() {
  local user="$1"
  log "Удаление collaborator ${user} с ${GITHUB_REPO}"
  gh api "repos/${OWNER}/${REPO}/collaborators/${user}" -X DELETE
  log "Collaborator доступ отозван."
}

cmd_revoke() {
  local user="${1:?usage: $0 revoke <github_username>}"
  sanitize_user "${user}"
  require_gh
  [[ "${user}" == "durygus" ]] && die "Нельзя отозвать доступ у себя через скрипт"

  local revoked=false
  if team_exists && gh api "orgs/${OWNER}/teams/${READERS_TEAM}/memberships/${user}" --jq .state >/dev/null 2>&1; then
    cmd_revoke_team "${user}"
    revoked=true
  fi
  if gh api "repos/${OWNER}/${REPO}/collaborators/${user}" --jq .login >/dev/null 2>&1; then
    local perm
    perm="$(gh api "repos/${OWNER}/${REPO}/collaborators/${user}/permission" --jq .permission)"
    if [[ "${perm}" != "admin" ]]; then
      cmd_revoke_collaborator "${user}"
      revoked=true
    fi
  fi
  [[ "${revoked}" == true ]] || die "У ${user} нет read-доступа через team/collaborator на этом repo"
}

cmd_grant() {
  local user="${1:?usage: $0 grant <github_username> [--collaborator]}"
  local mode="team"
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --collaborator) mode="collaborator" ;;
      *) die "Неизвестный аргумент: $1" ;;
    esac
    shift
  done

  sanitize_user "${user}"
  require_gh
  if ! user_exists "${user}"; then
    die "GitHub user не найден: ${user}"
  fi

  if [[ "${mode}" == "collaborator" ]]; then
    cmd_grant_collaborator "${user}"
  else
    cmd_grant_team "${user}"
  fi
}

cmd_list() {
  require_gh
  log "Repo: ${GITHUB_REPO}"
  echo
  echo "Collaborators:"
  gh api "repos/${OWNER}/${REPO}/collaborators" \
    --paginate \
    --jq '.[] | "  \(.login)\t\(.role_name)"' || true
  echo
  if team_exists; then
    echo "Team ${READERS_TEAM} (Read):"
    gh api "orgs/${OWNER}/teams/${READERS_TEAM}/members" \
      --paginate \
      --jq '.[] | "  \(.login)"' || true
    echo
    echo "Team ${READERS_TEAM} repos:"
    gh api "orgs/${OWNER}/teams/${READERS_TEAM}/repos" \
      --paginate \
      --jq ".[] | select(.name==\"${REPO}\") | \"  \(.full_name)\tpermission=\(.permissions.pull)\"" || true
  else
    echo "Team ${READERS_TEAM}: (ещё не создан — создастся при первом grant)"
  fi
  echo
  echo "Team gateway-engineers (Write):"
  gh api "orgs/${OWNER}/teams/pam-engineers/members" \
    --paginate \
    --jq '.[] | "  \(.login)"' 2>/dev/null || echo "  (team не найден)"
}

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Read-only доступ к ${GITHUB_REPO} (без deploy keys).
Инженер клонирует через свой SSH-ключ в GitHub Settings.

Commands:
  grant <github_user> [--collaborator]   Выдать Read (team ${READERS_TEAM} или outside collaborator)
  revoke <github_user>                 Отозвать Read
  list                                   Кто имеет доступ

Aliases: create → grant

Repo: GITHUB_REPO=${GITHUB_REPO}
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
    grant|create) cmd_grant "$@" ;;
    revoke)       cmd_revoke "$@" ;;
    list)         cmd_list ;;
    -h|--help|help|"") usage ;;
    *) die "Неизвестная команда: ${cmd}. $0 --help" ;;
  esac
}

main "$@"
