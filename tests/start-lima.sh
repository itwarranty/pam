#!/usr/bin/env bash
# Запускает Lima VM с конфигом Rocky 9 (repo доступен через writable mount ~).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTANCE_NAME="${LIMA_INSTANCE_NAME:-pam-prod}"

echo "[gateway] Repo (via ~ mount): ${REPO_ROOT}"
echo "[gateway] Starting VM:        ${INSTANCE_NAME}"

if limactl list "${INSTANCE_NAME}" 2>/dev/null | grep -q "${INSTANCE_NAME}"; then
  limactl start "${INSTANCE_NAME}"
else
  limactl start --name="${INSTANCE_NAME}" "${SCRIPT_DIR}/lima-rocky9.yaml"
fi

echo ""
echo "SSH:     limactl shell ${INSTANCE_NAME}"
echo "Ansible: limactl show-ssh ${INSTANCE_NAME}"
echo "Deploy:  ansible-playbook -i inventory/local-lima.yml site.yml"
