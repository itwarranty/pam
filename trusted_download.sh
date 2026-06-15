#!/usr/bin/env bash
# MT: Bastion — подготовка доверенного offline-артефакта для Air Gap.
#
# Запуск на build-машине с доступом к реестру образов (один раз):
#   ./trusted_download.sh
#
# Строгий MFA (без nullok) — по умолчанию:
#   MFA_STRICT=1 ./trusted_download.sh
#
# Результат: trusted_upstream_packages/mt_bastion_image.tar + SHA256SUMS

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${TRUSTED_FILES_DIR:-/tmp/trusted_upstream_packages}"
CONTAINERFILE="${SCRIPT_DIR}/build/Containerfile"
IMAGE_NAME="${BASTION_IMAGE_NAME:-mt_bastion_secure}"
IMAGE_TAG="${BASTION_IMAGE_TAG:-latest}"
IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
TAR_PATH="${OUTPUT_DIR}/mt_bastion_image.tar"
CHECKSUMS_FILE="${OUTPUT_DIR}/SHA256SUMS"
MFA_STRICT="${MFA_STRICT:-1}"

log() { printf '[mt-bastion] %s\n' "$*"; }
die() { printf '[mt-bastion] ERROR: %s\n' "$*" >&2; exit 1; }

if [ "${MFA_STRICT}" != "1" ] && [ "${BASTION_LAB_MODE:-0}" != "1" ]; then
  die "MFA_STRICT=${MFA_STRICT} запрещён политикой CSO. Prod-сборка: MFA_STRICT=1 (по умолчанию). Lab-only: BASTION_LAB_MODE=1 MFA_STRICT=0."
fi

command -v podman >/dev/null 2>&1 || die "podman не найден. Установите Podman для сборки образа."
[[ -f "${CONTAINERFILE}" ]] || die "Containerfile не найден: ${CONTAINERFILE}"

mkdir -p "${OUTPUT_DIR}"

log "Сборка образа (MFA_STRICT=${MFA_STRICT}) ..."
podman build \
  --file "${CONTAINERFILE}" \
  --build-arg "MFA_STRICT=${MFA_STRICT}" \
  --tag "${IMAGE_REF}" \
  --layers \
  "${SCRIPT_DIR}"

log "Экспорт образа в ${TAR_PATH} ..."
rm -f "${TAR_PATH}"
podman save --output "${TAR_PATH}" "${IMAGE_REF}"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${TAR_PATH}" > "${CHECKSUMS_FILE}"
elif command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "${TAR_PATH}" > "${CHECKSUMS_FILE}"
else
  die "Не найден sha256sum/shasum для генерации контрольной суммы."
fi

log "Готово."
log "  Образ:    ${IMAGE_REF}"
log "  Архив:    ${TAR_PATH}"
log "  Checksum: ${CHECKSUMS_FILE}"
log ""
log "Проверка на целевом хосте перед деплоем:"
log "  cd ${OUTPUT_DIR} && sha256sum -c SHA256SUMS"
log "  ansible-playbook site.yml"
