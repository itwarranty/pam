#!/usr/bin/env python3
"""Strict argv executor for access:audit — no shell, no eval."""
from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Iterable, Sequence


AUDIT_DIR = os.environ.get("PAM_AUDIT_LOG_DIR", "/var/log/pam_sessions")

# Reject shell metacharacters, globs, and relative-path tricks in tokens.
_FORBIDDEN = re.compile(
    r"[\$`;&|<>\n\r\x00*?\[\]\\]|^\.\./|/\.\./|^\.$"
)


@dataclass(frozen=True)
class CommandSpec:
    executable: str
    allowed_options: frozenset[str]
    path_positions: frozenset[int] | str  # "all_non_option" or explicit indices (1-based args)
    extra_env: dict[str, str] | None = None
    option_validator: Callable[[str, str], bool] | None = None


def _paths_from_argv(argv: Sequence[str], spec: CommandSpec) -> Iterable[str]:
    if spec.path_positions == "all_non_option":
        for arg in argv[1:]:
            if arg.startswith("-"):
                continue
            yield arg
    else:
        for idx in spec.path_positions:
            if idx < len(argv):
                yield argv[idx]


def _validate_options(argv: Sequence[str], spec: CommandSpec) -> None:
    idx = 1
    while idx < len(argv):
        arg = argv[idx]
        if not arg.startswith("-"):
            idx += 1
            continue
        if arg not in spec.allowed_options:
            raise ValueError(f"option not permitted: {arg}")
        if spec.option_validator and not spec.option_validator(arg, argv[idx + 1] if idx + 1 < len(argv) else ""):
            raise ValueError(f"option not permitted: {arg}")
        idx += 2 if arg in {"-n"} else 1


def resolve_audit_path(raw: str) -> str:
    if _FORBIDDEN.search(raw):
        raise ValueError("path denied")
    resolved = os.path.realpath(raw)
    audit_root = os.path.realpath(AUDIT_DIR)
    if resolved == audit_root or resolved.startswith(audit_root + os.sep):
        return resolved
    raise ValueError("path denied")


def tokenize(line: str) -> list[str]:
    line = line.strip()
    if not line:
        return []
    for part in line.split():
        if _FORBIDDEN.search(part):
            raise ValueError("forbidden syntax")
    return line.split()


def _tail_option_ok(opt: str, _next: str) -> bool:
    return opt not in {"-f", "-F"}


_COMMANDS: dict[str, CommandSpec] = {
    "less": CommandSpec(
        executable="/usr/bin/less",
        allowed_options=frozenset({"-N", "-S", "-F", "-R", "-M", "-E"}),
        path_positions="all_non_option",
        extra_env={"LESS": "-E -F -R -M"},
    ),
    "cat": CommandSpec(
        executable="/bin/cat",
        allowed_options=frozenset({"-n"}),
        path_positions="all_non_option",
    ),
    "ls": CommandSpec(
        executable="/bin/ls",
        allowed_options=frozenset({"-l", "-a", "-h", "-1"}),
        path_positions="all_non_option",
    ),
    "head": CommandSpec(
        executable="/usr/bin/head",
        allowed_options=frozenset({"-n"}),
        path_positions="all_non_option",
    ),
    "tail": CommandSpec(
        executable="/usr/bin/tail",
        allowed_options=frozenset({"-n"}),
        path_positions="all_non_option",
        option_validator=_tail_option_ok,
    ),
    "grep": CommandSpec(
        executable="/bin/grep",
        allowed_options=frozenset({"-i", "-n", "-E", "-F", "-w"}),
        path_positions={2},
    ),
    "sha256sum": CommandSpec(
        executable="/usr/bin/sha256sum",
        allowed_options=frozenset(),
        path_positions="all_non_option",
    ),
    "pwd": CommandSpec(
        executable="/bin/pwd",
        allowed_options=frozenset(),
        path_positions=frozenset(),
    ),
    "echo": CommandSpec(
        executable="/bin/echo",
        allowed_options=frozenset({"-n"}),
        path_positions=frozenset(),
    ),
}


def build_argv(tokens: Sequence[str]) -> list[str]:
    if not tokens:
        return []
    cmd = tokens[0]
    if cmd in {"exit", "logout", "help"}:
        return list(tokens)
    spec = _COMMANDS.get(cmd)
    if spec is None:
        raise ValueError(f"command not permitted: {cmd}")
    _validate_options(tokens, spec)
    argv = [spec.executable, *tokens[1:]]
    path_args = list(_paths_from_argv(tokens, spec))
    for raw in path_args:
        canonical = resolve_audit_path(raw)
        for i in range(1, len(argv)):
            if argv[i] == raw:
                argv[i] = canonical
                break
    return argv


def audit_syslog(event: str, detail: str) -> None:
    subprocess.run(
        ["/usr/local/bin/pam-syslog.sh", event, detail],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def execute_line(line: str) -> int:
    try:
        tokens = tokenize(line)
    except ValueError as exc:
        audit_syslog("pam-deny", f"audit user={os.environ.get('USER', 'unknown')} parse={exc}")
        print("[SSH PAM CSO] Command not permitted for audit role.", file=sys.stderr)
        return 1

    if not tokens:
        return 0

    cmd = tokens[0]
    if cmd in {"exit", "logout"}:
        raise SystemExit(0)
    if cmd == "help":
        print(
            f"Allowed: {', '.join(sorted(_COMMANDS))}, pwd, exit\n"
            f"Paths must be under {AUDIT_DIR}"
        )
        return 0

    try:
        argv = build_argv(tokens)
    except ValueError as exc:
        audit_syslog(
            "pam-deny",
            f"audit user={os.environ.get('USER', 'unknown')} denied reason={exc}",
        )
        msg = str(exc)
        if msg == "path denied":
            print("[SSH PAM CSO] Path denied.", file=sys.stderr)
        elif "option" in msg or "command" in msg:
            print("[SSH PAM CSO] Command not permitted for audit role.", file=sys.stderr)
        else:
            print("[SSH PAM CSO] Command not permitted for audit role.", file=sys.stderr)
        return 1

    spec = _COMMANDS[tokens[0]]
    env = os.environ.copy()
    if spec.extra_env:
        env.update(spec.extra_env)

    try:
        result = subprocess.run(argv, env=env)
        return result.returncode
    except OSError as exc:
        audit_syslog(
            "pam-deny",
            f"audit user={os.environ.get('USER', 'unknown')} exec_error={exc}",
        )
        print("[SSH PAM CSO] Command failed.", file=sys.stderr)
        return 1


def main() -> None:
    if len(sys.argv) > 1 and sys.argv[1] == "--exec":
        line = sys.argv[2] if len(sys.argv) > 2 else sys.stdin.read()
        raise SystemExit(execute_line(line))

    print(f"SSH PAM audit shell — read-only under {AUDIT_DIR}. Type 'help' or 'exit'.")
    while True:
        try:
            line = input("audit> ")
        except EOFError:
            break
        if not line.strip():
            continue
        try:
            execute_line(line)
        except SystemExit as exc:
            raise SystemExit(exc.code) from None


if __name__ == "__main__":
    main()
