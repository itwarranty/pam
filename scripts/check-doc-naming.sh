#!/usr/bin/env bash
# Fail if removed MT/bastion/gateway-home naming appears in current operational docs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

PATTERN='(/home/gateway|/home/bastion|ssh_bastion|mt-bastion|bastion_)'
paths=(docs scripts group_vars tasks README.md)
exclude=(scripts/check-doc-naming.sh)

hits=""
for path in "${paths[@]}"; do
  [[ -e "${path}" ]] || continue
  while IFS= read -r file; do
    skip=0
    for ex in "${exclude[@]}"; do
      [[ "${file}" == "${ex}" ]] && skip=1 && break
    done
    [[ "${skip}" -eq 1 ]] && continue
    while IFS= read -r line; do
      hits+="${line}"$'\n'
    done < <(grep -nE "${PATTERN}" "${file}" 2>/dev/null || true)
  done < <(find "${path}" -type f \( -name '*.md' -o -name '*.yml' -o -name '*.sh' \) 2>/dev/null)
done

if [[ -n "${hits}" ]]; then
  echo "Documentation naming check failed (legacy identifiers in current docs):" >&2
  printf '%s' "${hits}" >&2
  exit 1
fi

echo "Documentation naming check passed."
