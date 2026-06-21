#!/usr/bin/env bash
# Генерирует Lima-конфиг с абсолютным путём к репозиторию и запускает VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTANCE_NAME="${LIMA_INSTANCE_NAME:-bastion-prod}"
RENDERED="/tmp/bastion-lima-${INSTANCE_NAME}.yaml"

sed "s|__BASTION_REPO__|${REPO_ROOT}|g" "${SCRIPT_DIR}/lima-rocky9.yaml" > "${RENDERED}"

echo "[bastion] Lima config: ${RENDERED}"
echo "[bastion] Repo mount:   ${REPO_ROOT}"
echo "[bastion] Starting VM:  ${INSTANCE_NAME}"

if limactl list "${INSTANCE_NAME}" 2>/dev/null | grep -q "${INSTANCE_NAME}"; then
  limactl start "${INSTANCE_NAME}"
else
  limactl start --name="${INSTANCE_NAME}" "${RENDERED}"
fi

echo ""
echo "SSH:     limactl shell ${INSTANCE_NAME}"
echo "Ansible: limactl show-ssh ${INSTANCE_NAME}"
echo "Deploy:  ansible-playbook -i inventory/local-lima.yml site.yml"
