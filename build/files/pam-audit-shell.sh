#!/bin/bash
# Restricted read-only shell for access: audit (paths under /var/log/pam_sessions only).
set -euo pipefail

export PAM_AUDIT_LOG_DIR="${PAM_AUDIT_LOG_DIR:-/var/log/pam_sessions}"
exec /usr/local/bin/pam-audit-exec.py
