#!/bin/sh
# Wrapper for bastion-side PTY command policy v2.
set -eu
exec python3 /usr/local/bin/bastion-pty-inspector.py "$@"
