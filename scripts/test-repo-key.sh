#!/usr/bin/env bash
# Единый тестовый SSH-ключ: GitHub (read) + SSH PAM (оператор).
#
#   ./scripts/test-repo-key.sh create tester-01 --bastion --apply
#   ./scripts/test-repo-key.sh revoke tester-01 --apply
#   ./scripts/test-repo-key.sh apply-dev
#
# Переменные:
#   GITHUB_REPO, TEST_ACCESS_BASE, ANSIBLE_INVENTORY, BASTION_SSH_HOST, BASTION_SSH_PORT

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-itwarranty/itwarranty-pam}"
TEST_ACCESS_BASE="${TEST_ACCESS_BASE:-${HOME}/.bastion/test-access}"
TEST_OPERATORS_YML="${ROOT}/group_vars/dev/test_operators.yml"
LEGACY_KEYS_DIR="${ROOT}/keys/test"
KEY_TITLE_PREFIX="bastion-test"
BASTION_SSH_HOST="${BASTION_SSH_HOST:-127.0.0.1}"
BASTION_SSH_PORT="${BASTION_SSH_PORT:-2222}"
BASTION_TEST_PERMIT_OPEN="${BASTION_TEST_PERMIT_OPEN:-10.0.1.10:22}"
ANSIBLE_INVENTORY="${ANSIBLE_INVENTORY:-${ROOT}/inventory/local-lima.yml}"
OWNER="${GITHUB_REPO%%/*}"
REPO="${GITHUB_REPO#*/}"

user_dir() {
  printf '%s/%s' "${TEST_ACCESS_BASE}" "$1"
}

user_priv_key() {
  printf '%s/%s.key' "$(user_dir "$1")" "$1"
}

user_pub_key() {
  printf '%s/%s.key.pub' "$(user_dir "$1")" "$1"
}

ensure_user_dir() {
  local name="$1"
  mkdir -p "${TEST_ACCESS_BASE}"
  mkdir -p "$(user_dir "${name}")"
  chmod 700 "${TEST_ACCESS_BASE}" 2>/dev/null || true
  chmod 700 "$(user_dir "${name}")" 2>/dev/null || true
}

log() { printf '[test-repo-key] %s\n' "$*" >&2; }
die() { printf '[test-repo-key] ERROR: %s\n' "$*" >&2; exit 1; }

require_gh() {
  command -v gh >/dev/null 2>&1 || die "Нужен gh CLI: https://cli.github.com/"
  command -v ssh-keygen >/dev/null 2>&1 || die "Нужен ssh-keygen"
  gh auth status >/dev/null 2>&1 || die "gh не авторизован: gh auth login"
}

cmd_apply_dev() {
  command -v ansible-playbook >/dev/null 2>&1 || die "Нужен ansible-playbook"
  log "Применение операторов на dev: ansible-playbook -i ${ANSIBLE_INVENTORY}"
  ansible-playbook -i "${ANSIBLE_INVENTORY}" "${ROOT}/site.yml"
}

maybe_apply_dev() {
  [[ "${APPLY_DEV:-false}" == true ]] && cmd_apply_dev
}

sanitize_name() {
  local name="$1"
  [[ "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$ ]] \
    || die "Имя ключа: [a-zA-Z0-9._-], 1–63 символа"
}

key_title() {
  printf '%s-%s' "${KEY_TITLE_PREFIX}" "$1"
}

gen_mfa_secret() {
  python3 -c 'import secrets, base64; print(base64.b32encode(secrets.token_bytes(20)).decode().rstrip("="))'
}

api_keys() {
  gh api "repos/${OWNER}/${REPO}/keys" "$@"
}

find_key_id_by_name() {
  local name="$1"
  local title
  title="$(key_title "${name}")"
  gh api "repos/${OWNER}/${REPO}/keys" \
    --jq ".[] | select(.title==\"${title}\") | .id" | head -1
}

register_deploy_key() {
  local name="$1"
  local pub_file="$2"
  local title
  title="$(key_title "${name}")"

  [[ -f "${pub_file}" ]] || die "Public key не найден: ${pub_file}"

  log "Регистрация read-only ключа на GitHub: ${title}"
  if ! gh api "repos/${OWNER}/${REPO}/keys" \
    -X POST \
    -f title="${title}" \
    -f key="$(cat "${pub_file}")" \
    -F read_only=true \
    --jq '{id, title, read_only}'; then
    die "Не удалось зарегистрировать ключ. Deploy keys disabled? ${OWNER} → Settings → Member privileges → Deploy keys → Enabled."
  fi
}

pubkey_file_for() {
  local name="$1"
  local pub
  pub="$(user_pub_key "${name}")"
  [[ -f "${pub}" ]] && printf '%s' "${pub}" && return 0
  # legacy (до ~/.bastion/test-access)
  pub="${LEGACY_KEYS_DIR}/${name}.key.pub"
  [[ -f "${pub}" ]] && printf '%s' "${pub}" && return 0
  pub="${LEGACY_KEYS_DIR}/${name}.pub"
  [[ -f "${pub}" ]] && printf '%s' "${pub}" && return 0
  return 1
}

registry_file() {
  printf '%s/meta.yml' "$(user_dir "$1")"
}

bastion_registered() {
  [[ -f "$(registry_file "$1")" ]]
}

register_bastion_operator() {
  local name="$1"
  local access="${2:-jump}"
  local pub_file
  pub_file="$(pubkey_file_for "${name}")" || die "Public key не найден для ${name}"

  [[ "${access}" == "jump" || "${access}" == "shell" ]] \
    || die "access: jump или shell"

  ensure_user_dir "${name}"
  local reg mfa pub_file
  pub_file="$(pubkey_file_for "${name}")"
  reg="$(registry_file "${name}")"

  if [[ -f "${reg}" ]]; then
    mfa="$(grep '^mfa_secret:' "${reg}" | awk '{print $2}')"
    log "шлюз: оператор ${name} уже в registry"
  else
    mfa="$(gen_mfa_secret)"
    cat >"${reg}" <<EOF
# AUTO: test-repo-key.sh — не редактировать
access: ${access}
mfa_secret: ${mfa}
email: ${name}@example.com
pubkey_file: ${pub_file}
EOF
    log "шлюз: добавлен оператор ${name} (${access})"
  fi

  sync_test_operators_yml
  printf '%s' "${mfa}"
}

unregister_bastion_operator() {
  local name="$1"
  local reg
  reg="$(registry_file "${name}")"
  if [[ -f "${reg}" ]]; then
    rm -f "${reg}"
    log "шлюз: удалён оператор ${name} из registry"
    sync_test_operators_yml
  fi
}

sync_test_operators_yml() {
  local names=() name reg access mfa email pub_file pub_ansible
  if [[ -d "${TEST_ACCESS_BASE}" ]]; then
    for reg in "${TEST_ACCESS_BASE}"/*/meta.yml; do
      [[ -f "${reg}" ]] || continue
      name="$(basename "$(dirname "${reg}")")"
      names+=("${name}")
    done
  fi

  {
    echo "---"
    echo "# AUTO: scripts/test-repo-key.sh --bastion (не редактировать)"
    echo "# Pubkey: ~/.bastion/test-access/<name>/ (admin HOME при ansible-playbook)"
    echo "bastion_operators_test:"
    if [[ ${#names[@]} -eq 0 ]]; then
      echo "  []"
    else
      for name in "${names[@]}"; do
        reg="$(registry_file "${name}")"
        access="$(grep '^access:' "${reg}" | awk '{print $2}')"
        mfa="$(grep '^mfa_secret:' "${reg}" | awk '{print $2}')"
        email="$(grep '^email:' "${reg}" | awk '{print $2}')"
        pub_file="$(grep '^pubkey_file:' "${reg}" | cut -d' ' -f2-)"
        cat <<YAML
  - name: ${name}
    email: ${email}
    pubkey: "{{ lookup('file', lookup('env', 'HOME') ~ '/.bastion/test-access/${name}/${name}.key.pub') }}"
    mfa_secret: ${mfa}
    access: ${access}
    permit_open:
      - "${BASTION_TEST_PERMIT_OPEN}"
YAML
      done
    fi
  } >"${TEST_OPERATORS_YML}"
  log "Обновлён ${TEST_OPERATORS_YML}"
}

otpauth_uri_for() {
  local name="$1"
  local mfa="$2"
  printf 'otpauth://totp/%s:%s@example.com?secret=%s&issuer=%s+Test' \
    "$(python3 -c "import urllib.parse; print(urllib.parse.quote('${BASTION_TOTP_ISSUER:-SSH PAM}'))")" \
    "${name}" "${mfa}" \
    "$(python3 -c "import urllib.parse; print(urllib.parse.quote('${BASTION_TOTP_ISSUER:-SSH PAM}'))")"
}

generate_totp_qr() {
  local otpauth_uri="$1"
  local png_out="$2"
  local ascii_out="$3"
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"

  command -v node >/dev/null 2>&1 || die "Нужен Node.js: https://nodejs.org/"
  if [[ ! -d "${script_dir}/node_modules/qrcode" ]]; then
    log "Установка qrcode (npm install в scripts/)..."
    (cd "${script_dir}" && npm install --omit=dev --no-audit --no-fund)
  fi
  node "${script_dir}/gen-totp-qr.mjs" "${otpauth_uri}" "${png_out}" "${ascii_out}"
}

write_onboarding_package() {
  local name="$1"
  local mfa="${2:-}"
  local access="${3:-jump}"
  local udir priv onboarding qr_png qr_ascii otpauth=""
  udir="$(user_dir "${name}")"
  priv="$(user_priv_key "${name}")"
  onboarding="${udir}/${name}.onboarding.txt"
  qr_png="${udir}/${name}.totp.png"
  qr_ascii="${udir}/${name}.totp.qr.txt"

  [[ -f "${priv}" ]] || die "Private key не найден: ${priv}"

  {
    cat <<HDR
SSH PAM — тестовый onboarding: ${name}
Каталог: ${udir}
Сгенерировано: $(date -u +"%Y-%m-%dT%H:%M:%SZ") UTC

Передайте тестировщику (защищённый канал) файлы из каталога ${udir}/

================================================================================
1. PRIVATE KEY (отдельный файл — НЕ в этом документе)
================================================================================
  ${priv}

  Тестировщик:
    chmod 600 ${name}.key
    mv ${name}.key ~/.ssh/${name}.key

HDR
    cat <<'HDR2'

================================================================================
2. SSH CONFIG (~/.ssh/config)
================================================================================
HDR2
    cat <<CFG
Host github.com-bastion-test
  HostName github.com
  User git
  IdentityFile ~/.ssh/${name}.key
  IdentitiesOnly yes

Host bastion-test
  HostName ${BASTION_SSH_HOST}
  Port ${BASTION_SSH_PORT}
  User ${name}
  IdentityFile ~/.ssh/${name}.key
  IdentitiesOnly yes

CFG
    cat <<'HDR3'
================================================================================
3. GIT (read-only)
================================================================================
HDR3
    echo "  git clone git@github.com-bastion-test:${GITHUB_REPO}.git"
    echo ""
  } >"${onboarding}"

  if [[ -n "${mfa}" ]]; then
    otpauth="$(otpauth_uri_for "${name}" "${mfa}")"
    generate_totp_qr "${otpauth}" "${qr_png}" "${qr_ascii}" \
      || die "Не удалось сгенерировать QR (нужен Node.js + npm install в scripts/)"

    {
      cat <<HDR4
================================================================================
4. TOTP (один раз в Google Authenticator / Authy)
================================================================================
Secret (ручной ввод): ${mfa}
otpauth URI:
${otpauth}

Отсканируйте QR в приложении — PNG: ${name}.totp.png
Или ASCII QR ниже (увеличьте шрифт / моноширинный):

HDR4
      cat "${qr_ascii}"
      cat <<HDR5

При ssh bastion-test введите 6 цифр из приложения (к вам не обращаться).

================================================================================
5. BASTION SSH
================================================================================
  ssh bastion-test

Access: ${access}
Admin: create/revoke с --apply применяет bastion автоматически.
  ./scripts/test-repo-key.sh apply-dev

HDR5
    } >>"${onboarding}"
  else
    cat >>"${onboarding}" <<'HDR6'

================================================================================
4. BASTION
================================================================================
Не включён. Admin: ./scripts/test-repo-key.sh bastion-enable NAME

HDR6
  fi

  cat >>"${onboarding}" <<EOF

================================================================================
ОТЗЫВ ДОСТУПА (admin)
================================================================================
  ./scripts/test-repo-key.sh revoke ${name}
EOF

  chmod 600 "${onboarding}"
  [[ -f "${qr_png}" ]] && chmod 644 "${qr_png}"
  rm -f "${qr_ascii}"
  log "Onboarding: ${onboarding}"
  [[ -n "${mfa}" && -f "${qr_png}" ]] && log "TOTP QR (PNG): ${qr_png}"
}

remove_onboarding_files() {
  local name="$1"
  local udir
  udir="$(user_dir "${name}")"
  rm -f \
    "${udir}/${name}.onboarding.txt" \
    "${udir}/${name}.totp.png" \
    "${udir}/${name}.totp.qr.txt"
}

remove_user_data() {
  local name="$1"
  local udir legacy
  udir="$(user_dir "${name}")"
  if [[ -d "${udir}" ]]; then
    rm -rf "${udir}"
    log "Удалён каталог ${udir}"
  fi
  # legacy
  legacy="${LEGACY_KEYS_DIR}/${name}.key"
  if [[ -f "${legacy}" ]] || [[ -d "${LEGACY_KEYS_DIR}/registry" ]]; then
    rm -f \
      "${LEGACY_KEYS_DIR}/${name}.key" \
      "${LEGACY_KEYS_DIR}/${name}.pub" \
      "${LEGACY_KEYS_DIR}/${name}.key.pub" \
      "${LEGACY_KEYS_DIR}/${name}.onboarding.txt" \
      "${LEGACY_KEYS_DIR}/${name}.totp.png"
    rm -f "${LEGACY_KEYS_DIR}/registry/${name}.yml"
  fi
}

print_usage_instructions() {
  local name="$1"
  local priv
  priv="$(user_priv_key "${name}")"
  local mfa="${2:-}"
  local access="${3:-}"

  cat <<EOF

--- Единый тестовый доступ: ${name} ---

Private key (один файл на Git + gateway):
  ${priv}

~/.ssh/config:

  Host github.com-bastion-test
    HostName github.com
    User git
    IdentityFile ${priv}
    IdentitiesOnly yes

  Host bastion-test
    HostName ${BASTION_SSH_HOST}
    Port ${BASTION_SSH_PORT}
    User ${name}
    IdentityFile ${priv}
    IdentitiesOnly yes

Git:
  git clone git@github.com-bastion-test:${GITHUB_REPO}.git

EOF

  if [[ -n "${mfa}" ]]; then
    cat <<EOF
Gateway (тот же ключ + TOTP):
  ssh bastion-test

  TOTP secret (Google Authenticator): ${mfa}
  otpauth://totp/SSH%20PAM:${name}@example.com?secret=${mfa}&issuer=SSH+PAM+Test

  Dev: после create --bastion выполните redeploy:
  ansible-playbook -i inventory/local-lima.yml site.yml

EOF
  fi

  cat <<EOF
Отозвать всё:
  ./scripts/test-repo-key.sh revoke ${name}

EOF

  write_onboarding_package "${name}" "${mfa}" "${access:-jump}"
}

cmd_migrate_legacy() {
  local name="${1:?usage: $0 migrate <name>}"
  sanitize_name "${name}"
  local legacy_priv="${LEGACY_KEYS_DIR}/${name}.key"
  [[ -f "${legacy_priv}" ]] || die "Legacy ключ не найден: ${legacy_priv}"
  ensure_user_dir "${name}"
  local priv pub
  priv="$(user_priv_key "${name}")"
  pub="$(user_pub_key "${name}")"
  cp "${legacy_priv}" "${priv}"
  cp "${legacy_priv}.pub" "${pub}" 2>/dev/null || cp "${LEGACY_KEYS_DIR}/${name}.key.pub" "${pub}"
  chmod 600 "${priv}" "${pub}"
  local udir
  udir="$(user_dir "${name}")"
  for f in "${name}.onboarding.txt" "${name}.totp.png"; do
    [[ -f "${LEGACY_KEYS_DIR}/${f}" ]] && cp "${LEGACY_KEYS_DIR}/${f}" "${udir}/${f}"
  done
  [[ -f "${LEGACY_KEYS_DIR}/registry/${name}.yml" ]] && cp "${LEGACY_KEYS_DIR}/registry/${name}.yml" "$(registry_file "${name}")"
  sync_test_operators_yml
  rm -rf "${LEGACY_KEYS_DIR}/${name}.key" "${LEGACY_KEYS_DIR}/${name}.key.pub" \
    "${LEGACY_KEYS_DIR}/${name}.onboarding.txt" "${LEGACY_KEYS_DIR}/${name}.totp.png" \
    "${LEGACY_KEYS_DIR}/registry/${name}.yml" 2>/dev/null || true
  log "Перенесено в $(user_dir "${name}")"
}

cmd_create() {
  local name=""
  local force=false
  local bastion=false
  local access="jump"
  APPLY_DEV=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=true ;;
      --bastion) bastion=true ;;
      --apply) APPLY_DEV=true ;;
      --access)
        shift
        access="${1:?--access jump|shell}"
        ;;
      -*) die "Неизвестный аргумент: $1" ;;
      *)
        [[ -z "${name}" ]] || die "usage: $0 create <name> [--bastion] [--access jump|shell] [--force]"
        name="$1"
        ;;
    esac
    shift
  done
  [[ -n "${name}" ]] || die "usage: $0 create <name> [--bastion] [--access jump|shell] [--force]"
  sanitize_name "${name}"
  require_gh

  if [[ -n "$(find_key_id_by_name "${name}")" ]]; then
    die "Ключ уже на GitHub: $(key_title "${name}") (revoke или bastion-enable)"
  fi

  ensure_user_dir "${name}"
  local priv pub
  priv="$(user_priv_key "${name}")"
  pub="$(user_pub_key "${name}")"

  if [[ -f "${priv}" ]]; then
    if [[ "${force}" == true ]]; then
      remove_user_data "${name}"
      ensure_user_dir "${name}"
    else
      die "Ключ уже есть: ${priv} (revoke ${name} или create --force)"
    fi
  fi

  log "Генерация ed25519: ${priv}"
  ssh-keygen -t ed25519 -f "${priv}" -N "" -C "$(key_title "${name}")@example.com"

  if ! register_deploy_key "${name}" "${pub}"; then
    rm -f "${priv}" "${pub}"
    exit 1
  fi

  chmod 600 "${priv}" "${pub}"

  local mfa=""
  if [[ "${bastion}" == true ]]; then
    mfa="$(register_bastion_operator "${name}" "${access}")"
  fi

  print_usage_instructions "${name}" "${mfa}" "${access}"
  maybe_apply_dev
}

cmd_onboarding() {
  local name="${1:?usage: $0 onboarding <name>}"
  sanitize_name "${name}"
  local mfa="" access="jump" reg
  reg="$(registry_file "${name}")"
  if [[ -f "${reg}" ]]; then
    mfa="$(grep '^mfa_secret:' "${reg}" | awk '{print $2}')"
    access="$(grep '^access:' "${reg}" | awk '{print $2}')"
  fi
  pubkey_file_for "${name}" >/dev/null || die "Нет ключа для ${name}"
  write_onboarding_package "${name}" "${mfa}" "${access}"
  log "Готово: $(user_dir "${name}")/${name}.onboarding.txt"
}

cmd_bastion_enable() {
  local name="${1:?usage: $0 bastion-enable <name> [--access jump|shell] [--apply]}"
  local access="jump"
  APPLY_DEV=false
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) APPLY_DEV=true ;;
      --access)
        shift
        access="${1:?--access jump|shell}"
        ;;
      *) die "Неизвестный аргумент: $1" ;;
    esac
    shift
  done
  sanitize_name "${name}"
  pubkey_file_for "${name}" >/dev/null || die "Нет pubkey для ${name} — сначала create"

  local mfa
  mfa="$(register_bastion_operator "${name}" "${access}")"
  print_usage_instructions "${name}" "${mfa}" "${access}"
  maybe_apply_dev
}

cmd_import() {
  local name="${1:?usage: $0 import <name> <path-to.pub>}"
  local pub_src="${2:?usage: $0 import <name> <path-to.pub>}"
  sanitize_name "${name}"
  require_gh

  if [[ -n "$(find_key_id_by_name "${name}")" ]]; then
    die "Ключ уже на GitHub: $(key_title "${name}")"
  fi

  ensure_user_dir "${name}"
  local pub_copy
  pub_copy="$(user_pub_key "${name}")"
  cp "${pub_src}" "${pub_copy}"
  chmod 644 "${pub_copy}"

  if ! register_deploy_key "${name}" "${pub_copy}"; then
    rm -f "${pub_copy}"
    exit 1
  fi

  log "Зарегистрирован public key ${name} (private key у тестера)"
  log "Отозвать: ./scripts/test-repo-key.sh revoke ${name}"
}

cmd_list() {
  require_gh
  log "GitHub deploy keys (read-only) на ${GITHUB_REPO}:"
  api_keys --jq '.[] | "  id=\(.id)  read_only=\(.read_only)  title=\(.title)"' || echo "  (пусто)"
  echo
  log "Каталог тестовых ключей: ${TEST_ACCESS_BASE}"
  echo
  if [[ -d "${TEST_ACCESS_BASE}" ]]; then
    log "Персональные каталоги:"
    for udir in "${TEST_ACCESS_BASE}"/*/; do
      [[ -d "${udir}" ]] || continue
      name="$(basename "${udir}")"
      access=""
      [[ -f "${udir}/meta.yml" ]] && access="$(grep '^access:' "${udir}/meta.yml" | awk '{print $2}')"
      echo "  ${name}/  access=${access:-git-only}"
      find "${udir}" -maxdepth 1 -type f 2>/dev/null | sort | sed 's/^/    /'
    done
    echo
  fi
  if [[ -d "${LEGACY_KEYS_DIR}" ]]; then
    log "Legacy (перенести: ./scripts/test-repo-key.sh migrate <name>):"
    find "${LEGACY_KEYS_DIR}" -maxdepth 2 -type f 2>/dev/null | sort | sed 's/^/  /' || true
  fi
}

cmd_revoke() {
  local arg=""
  APPLY_DEV=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply) APPLY_DEV=true ;;
      *) arg="$1" ;;
    esac
    shift
  done
  [[ -n "${arg}" ]] || die "usage: $0 revoke <name|key-id> [--apply]"
  require_gh

  local key_id=""
  local local_name=""

  if [[ ! "${arg}" =~ ^[0-9]+$ ]]; then
    sanitize_name "${arg}"
    local_name="${arg}"
    key_id="$(find_key_id_by_name "${arg}")"
  else
    key_id="${arg}"
    local title
    title="$(gh api "repos/${OWNER}/${REPO}/keys/${key_id}" --jq .title 2>/dev/null || true)"
    if [[ "${title}" == "${KEY_TITLE_PREFIX}-"* ]]; then
      local_name="${title#${KEY_TITLE_PREFIX}-}"
    fi
  fi

  if [[ -n "${key_id}" ]]; then
    log "Отзыв GitHub deploy key id=${key_id}"
    gh api "repos/${OWNER}/${REPO}/keys/${key_id}" -X DELETE || true
  elif [[ -n "${local_name}" ]]; then
    log "На GitHub ключ $(key_title "${local_name}") уже отсутствует"
  else
    die "Ключ не найден: ${arg}"
  fi

  if [[ -n "${local_name}" ]]; then
    unregister_bastion_operator "${local_name}"
    remove_user_data "${local_name}"
  fi

  log "Доступ отозван (Git + YAML). Gateway: apply-dev или --apply."
  maybe_apply_dev
}

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Единый SSH-ключ: GitHub read + (опционально) SSH PAM operator.

Commands:
  create <name> [--bastion] [--access jump|shell] [--force] [--apply]
  bastion-enable <name> [--access jump|shell] [--apply]
  onboarding <name>
  migrate <name>
  apply-dev                              Применить test_operators на dev (ansible)
  import <name> <file.pub>
  list
  revoke <name|key-id> [--apply]

Файлы: ${TEST_ACCESS_BASE}/<name>/  (default: ~/.bastion/test-access/)

Пример (полный цикл):
  $0 create tester-01 --bastion --apply
  $0 revoke tester-01 --apply

Org: Deploy keys → Enabled
  https://github.com/organizations/${OWNER}/settings/member_privileges
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
    create)         cmd_create "$@" ;;
    bastion-enable) cmd_bastion_enable "$@" ;;
    onboarding)     cmd_onboarding "$@" ;;
    migrate)        cmd_migrate_legacy "$@" ;;
    apply-dev)      cmd_apply_dev ;;
    import)         cmd_import "$@" ;;
    list)           cmd_list ;;
    revoke)         cmd_revoke "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "Неизвестная команда: ${cmd}. $0 --help" ;;
  esac
}

main "$@"
