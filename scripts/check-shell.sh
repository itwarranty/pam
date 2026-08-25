#!/usr/bin/env bash
# Shell script static checks (shellcheck when installed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

if ! command -v shellcheck >/dev/null 2>&1; then
  printf '[SKIP] shell-check: shellcheck not installed (brew install shellcheck / dnf install ShellCheck)\n'
  exit 0
fi

mapfile -t targets < <(
  find "${ROOT}/scripts" "${ROOT}/build/files" -type f -name '*.sh' \
    ! -name '*.example' 2>/dev/null | sort
)

for f in "${targets[@]}"; do
  if shellcheck -e SC1091,SC2034,SC2086,SC2154 "${f}"; then
    printf '[PASS] shellcheck: %s\n' "${f#${ROOT}/}"
  else
    failures=$((failures + 1))
  fi
done

if [[ "${failures}" -gt 0 ]]; then
  printf '[FAIL] shell-check: %s script(s) failed\n' "${failures}" >&2
  exit 1
fi
printf '[PASS] shell-check: %s script(s) OK\n' "${#targets[@]}"
