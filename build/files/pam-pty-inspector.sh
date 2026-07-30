#!/bin/sh
# Wrapper for gateway-side PTY command policy v2.
set -eu
exec python3 /usr/local/bin/pam-pty-inspector.py "$@"
