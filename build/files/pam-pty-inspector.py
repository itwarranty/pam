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


def disable_local_echo(fd):
    """Prevent IDE Cursor Position Reports from being echoed as "^[[row;colR".

    Cursor/VS Code inject CPR into the PTY; with ECHO on, the kernel paints them
    before any userspace filter can drop them. Remote ssh -tt still provides echo.
    """
    try:
        attrs = termios.tcgetattr(fd)
        attrs[3] = attrs[3] & ~(
            termios.ECHO | termios.ECHOE | termios.ECHOK | termios.ECHONL
        )
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
    except (termios.error, OSError):
        pass


# CSI final byte range (ECMA-48): drop CPR (…R) from IDE terminals.
_CPR_FINAL = ord("R")


class StdinCsiFilter:
    """Reassemble ESC/CSI across reads; drop Cursor Position Reports."""

    def __init__(self):
        self._esc = bytearray()

    def feed(self, data: bytes) -> bytes:
        out = bytearray()
        for byte in data:
            if self._esc:
                self._esc.append(byte)
                if len(self._esc) == 1:
                    continue
                if len(self._esc) == 2:
                    # ESC [ → CSI; any other second byte is not a CPR candidate.
                    if self._esc[1] != ord("["):
                        out.extend(self._esc)
                        self._esc.clear()
                    continue
                # CSI parameter/intermediate bytes, then final (0x40-0x7E).
                if 0x40 <= byte <= 0x7E:
                    if byte == _CPR_FINAL and re.fullmatch(
                        rb"\x1b\[\d+;\d+R", bytes(self._esc)
                    ):
                        self._esc.clear()
                        continue
                    out.extend(self._esc)
                    self._esc.clear()
                elif len(self._esc) > 64:
                    out.extend(self._esc)
                    self._esc.clear()
                continue
            if byte == 0x1B:
                self._esc.append(byte)
                continue
            out.append(byte)
        return bytes(out)


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
        stdin_fd = sys.stdin.fileno()
        stdin_flags = fcntl.fcntl(sys.stdin, fcntl.F_GETFL)
        fcntl.fcntl(sys.stdin, fcntl.F_SETFL, stdin_flags | os.O_NONBLOCK)
        disable_local_echo(stdin_fd)
    except OSError:
        pass

    line_buf = b""
    csi_filter = StdinCsiFilter()
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
            data = csi_filter.feed(data)
            if not data:
                continue
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
