#!/usr/bin/env python3
"""Gateway-side PTY inspector: denylist on operator input before forward to child (ssh/bash)."""
import errno
import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios


def load_patterns(path):
    patterns = []
    if not os.path.isfile(path):
        return patterns
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            patterns.append(re.compile(line))
    return patterns


def deny_match(line, patterns):
    for pat in patterns:
        if pat.search(line):
            return pat.pattern
    return None


def set_winsize(fd, row, col):
    winsize = struct.pack("HHHH", row, col, 0, 0)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)


def main():
    if len(sys.argv) < 2:
        sys.stderr.write("usage: pam-pty-inspector.py COMMAND [args...]\n")
        sys.exit(1)

    denylist = os.environ.get("PAM_DENYLIST", "/etc/ssh-pam/command_denylist")
    kill_on_deny = os.environ.get("PAM_GATEWAY_DENY_KILL", "0") == "1"
    mode = os.environ.get("PAM_GATEWAY_MODE", "shell")
    patterns = load_patterns(denylist)

    cmd = sys.argv[1:]
    pid, master_fd = pty.fork()
    if pid == 0:
        os.execvp(cmd[0], cmd)

    try:
        stdin_flags = fcntl.fcntl(sys.stdin, fcntl.F_GETFL)
        fcntl.fcntl(sys.stdin, fcntl.F_SETFL, stdin_flags | os.O_NONBLOCK)
    except OSError:
        pass

    line_buf = b""
    while True:
        rlist = [master_fd, sys.stdin]
        try:
            readable, _, _ = select.select(rlist, [], [], 0.2)
        except (OSError, ValueError):
            break

        if master_fd in readable:
            try:
                data = os.read(master_fd, 4096)
            except OSError:
                break
            if not data:
                break
            os.write(sys.stdout.fileno(), data)

        if sys.stdin in readable:
            try:
                data = os.read(sys.stdin.fileno(), 4096)
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    continue
                data = b""
            if not data:
                break
            for byte in data:
                if byte in (8, 127):
                    line_buf = line_buf[:-1]
                    os.write(master_fd, bytes([byte]))
                    continue
                if byte in (10, 13):
                    line = line_buf.decode("utf-8", errors="replace")
                    matched = deny_match(line, patterns) if patterns else None
                    if matched:
                        msg = f"[SSH PAM CSO] Command denied by policy (mode={mode}).\n"
                        os.write(sys.stdout.fileno(), msg.encode())
                        subprocess.run(
                            [
                                "/usr/local/bin/pam-syslog.sh",
                                "pam-deny",
                                f"mode={mode} user={os.environ.get('USER', 'unknown')} "
                                f"denied pattern={matched} cmd={line!r}",
                            ],
                            check=False,
                        )
                        line_buf = b""
                        if kill_on_deny:
                            os.kill(pid, signal.SIGTERM)
                            sys.exit(1)
                        continue
                    line_buf = b""
                    os.write(master_fd, bytes([byte]))
                else:
                    line_buf += bytes([byte])
                    os.write(master_fd, bytes([byte]))

        if pid and os.waitpid(pid, os.WNOHANG)[0] == pid:
            break

    try:
        _, status = os.waitpid(pid, 0)
        sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
    except OSError:
        sys.exit(0)


if __name__ == "__main__":
    main()
