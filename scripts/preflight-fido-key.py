#!/usr/bin/env python3
"""Validate operator pubkey or SSH user cert is FIDO-sk backed. Exit 0 pass, 1 fail."""
from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ED25519_SK = re.compile(r"^sk-ssh-ed25519@openssh\.com\s")
ECDSA_SK = re.compile(r"^sk-ecdsa-sha2-nistp256@openssh\.com\s")
CERT_LINE = re.compile(r"^-?\S+-cert-\S+@openssh\.com\s")


def allow_ecdsa() -> bool:
    return os.environ.get("PAM_FIDO_ECDSA_SK_ALLOWED", "0").lower() in (
        "1",
        "true",
        "yes",
    )


def strip_options(line: str) -> str:
    line = line.strip()
    if not line or line.startswith("#"):
        return ""
    parts = line.split()
    for idx, part in enumerate(parts):
        if part.startswith(("sk-", "ssh-", "ecdsa-")):
            return " ".join(parts[idx:])
    return line


def is_sk_pubkey(material: str) -> bool:
    if ED25519_SK.match(material):
        return True
    return allow_ecdsa() and bool(ECDSA_SK.match(material))


def cert_is_fido_backed(path: Path) -> bool:
    try:
        proc = subprocess.run(
            ["ssh-keygen", "-Lf", str(path)],
            capture_output=True,
            text=True,
            check=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        print(f"FIDO cert check failed: {exc}", file=sys.stderr)
        return False

    out = proc.stdout.lower()
    if "ssh-ed25519-sk" in out or "(ssh-ed25519-sk)" in out:
        return True
    if allow_ecdsa() and "ecdsa-sk" in out:
        return True
    print(f"Certificate not FIDO-sk backed:\n{proc.stdout}", file=sys.stderr)
    return False


def check_material(material: str) -> bool:
    material = strip_options(material)
    if not material:
        print("Empty key material", file=sys.stderr)
        return False

    if is_sk_pubkey(material):
        return True

    if CERT_LINE.match(material):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".cert.pub", delete=False
        ) as tmp:
            tmp.write(material + "\n")
            tmp_path = Path(tmp.name)
        try:
            return cert_is_fido_backed(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)

    print(f"Not a FIDO-sk pubkey or certificate: {material[:80]}...", file=sys.stderr)
    return False


def check_path(path: Path) -> bool:
    if not path.is_file():
        print(f"Path not found: {path}", file=sys.stderr)
        return False
    if path.suffix.endswith(".pub") or "-cert" in path.name:
        return cert_is_fido_backed(path)
    content = path.read_text(encoding="utf-8", errors="replace").strip()
    for line in content.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            return check_material(line)
    print(f"No key material in {path}", file=sys.stderr)
    return False


def main() -> int:
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        path = Path(arg)
        if path.is_file():
            ok = check_path(path)
        else:
            ok = check_material(arg)
    else:
        data = sys.stdin.read()
        lines = [ln.strip() for ln in data.splitlines() if ln.strip() and not ln.startswith("#")]
        if not lines:
            print("No input on stdin", file=sys.stderr)
            return 1
        ok = check_material(lines[0])

    if ok:
        print("PASS: FIDO-sk backed key")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
