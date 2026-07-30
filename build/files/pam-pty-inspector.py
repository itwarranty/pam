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
import tty


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


# Drop IDE Cursor Position Reports (Cursor/VS Code injects these into the PTY).
_CPR_FINAL = ord("R")
_CPR_BYTES_RE = re.compile(rb"\x1b\[\d+;\d+R")


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
                    if self._esc[1] != ord("["):
                        out.extend(self._esc)
                        self._esc.clear()
                    continue
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


def sync_winsize(src_fd: int, dst_fd: int) -> None:
    try:
        ws = fcntl.ioctl(src_fd, termios.TIOCGWINSZ, b"\0" * 8)
        fcntl.ioctl(dst_fd, termios.TIOCSWINSZ, ws)
    except OSError:
        pass


def prepare_parent_tty(fd: int):
    if not os.isatty(fd):
        return None
    saved = termios.tcgetattr(fd)
    # Raw + no local echo: remote ssh -tt provides character echo only.
    tty.setraw(fd, termios.TCSANOW)
    return saved


def restore_parent_tty(fd: int, saved) -> None:
    if saved is None:
        return
    try:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
    except (termios.error, OSError):
        pass


def strip_cpr_output(data: bytes) -> bytes:
    return _CPR_BYTES_RE.sub(b"", data)


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

    stdin_fd = sys.stdin.fileno()
    saved_tty = prepare_parent_tty(stdin_fd)
    sync_winsize(stdin_fd, master_fd)
    stop_loop = False

    def forward_signal(signum, _frame):
        nonlocal stop_loop
        stop_loop = True
        try:
            os.kill(pid, signum)
        except OSError:
            pass

    def on_winch(_signum, _frame):
        sync_winsize(stdin_fd, master_fd)

    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        try:
            signal.signal(sig, forward_signal)
        except (OSError, ValueError):
            pass
    try:
        signal.signal(signal.SIGWINCH, on_winch)
    except (OSError, ValueError):
        pass

    try:
        stdin_flags = fcntl.fcntl(stdin_fd, fcntl.F_GETFL)
        fcntl.fcntl(stdin_fd, fcntl.F_SETFL, stdin_flags | os.O_NONBLOCK)
    except OSError:
        pass

    line_buf = b""
    csi_filter = StdinCsiFilter()
    code = 0
    try:
        while not stop_loop:
            rlist = [master_fd, stdin_fd]
            try:
                readable, _, _ = select.select(rlist, [], [], 0.2)
            except InterruptedError:
                continue
            except OSError as exc:
                if exc.errno == errno.EINTR:
                    continue
                break

            if master_fd in readable:
                try:
                    data = os.read(master_fd, 4096)
                except OSError:
                    break
                if not data:
                    break
                data = strip_cpr_output(data)
                if data:
                    os.write(sys.stdout.fileno(), data)

            if stdin_fd in readable:
                try:
                    data = os.read(stdin_fd, 4096)
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
                    if byte == 0x03:
                        # Ctrl+C in raw mode — forward to remote session, no Python traceback.
                        line_buf = b""
                        os.write(master_fd, b"\x03")
                        continue
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
                                code = 1
                                stop_loop = True
                                break
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
            if os.WIFEXITED(status):
                code = os.WEXITSTATUS(status)
            elif os.WIFSIGNALED(status):
                sig = os.WTERMSIG(status)
                code = 128 + sig if sig else 1
        except OSError:
            pass
    finally:
        restore_parent_tty(stdin_fd, saved_tty)

    sys.exit(code)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
