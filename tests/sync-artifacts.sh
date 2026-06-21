#!/usr/bin/env bash
# Копирует Air Gap-артефакты с Mac-хоста в Lima VM.
set -euo pipefail

INSTANCE="${LIMA_INSTANCE_NAME:-bastion-prod}"
SRC="${TRUSTED_FILES_DIR:-/tmp/trusted_upstream_packages}"

for f in bastion_image.tar SHA256SUMS; do
  [[ -f "${SRC}/${f}" ]] || { echo "Missing ${SRC}/${f} — run ./trusted_download.sh first" >&2; exit 1; }
done

limactl shell "${INSTANCE}" -- sudo mkdir -p /tmp/trusted_upstream_packages
limactl copy "${SRC}/bastion_image.tar" "${INSTANCE}:/tmp/trusted_upstream_packages/bastion_image.tar"
limactl copy "${SRC}/SHA256SUMS" "${INSTANCE}:/tmp/trusted_upstream_packages/SHA256SUMS"

echo "[bastion] Artifacts synced to ${INSTANCE}:/tmp/trusted_upstream_packages/"
