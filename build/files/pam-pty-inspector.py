#!/usr/bin/env python3
"""Gateway-side PTY inspector: line-gated denylist before forward to child (ssh/bash)."""
import errno
import fcntl
import os
import pty
import re
import select
import signal
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


_CPR_FINAL = ord("R")
_CPR_BYTES_RE = re.compile(rb"\x1b\[\d+;\d+R")
_BRACKETED_PASTE_START = b"\x1b[200~"
_BRACKETED_PASTE_END = b"\x1b[201~"


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


class LineGate:
    """Buffer one logical command; local echo; forward only approved lines."""

    def __init__(self, stdout_fd: int):
        self.stdout_fd = stdout_fd
        self.line_buf = b""
        self.paste_buf = bytearray()

    def local_echo(self, data: bytes) -> None:
        if data:
            os.write(self.stdout_fd, data)

    def local_backspace(self) -> None:
        if not self.line_buf:
            return
        self.line_buf = self.line_buf[:-1]
        self.local_echo(b"\x08 \x08")

    def clear_buffer(self) -> None:
        self.line_buf = b""

    def append_printable(self, byte: int) -> None:
        if byte < 0x20 or byte == 0x7F:
            return
        self.line_buf += bytes([byte])
        self.local_echo(bytes([byte]))

    def submit_line(self, terminator: int) -> tuple[str, bool]:
        line = self.line_buf.decode("utf-8", errors="replace")
        payload = self.line_buf + bytes([terminator])
        self.line_buf = b""
        return line, payload

    def feed_paste(self, data: bytes):
        self.paste_buf.extend(data)
        while True:
            start = self.paste_buf.find(_BRACKETED_PASTE_START)
            if start == -1:
                if len(self.paste_buf) > 16:
                    self.paste_buf.clear()
                return []
            end = self.paste_buf.find(_BRACKETED_PASTE_END, start + len(_BRACKETED_PASTE_START))
            if end == -1:
                return []
            chunk = bytes(self.paste_buf[start + len(_BRACKETED_PASTE_START) : end])
            del self.paste_buf[: end + len(_BRACKETED_PASTE_END)]
            yield chunk


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


def emit_deny(mode: str, matched: str, line: str) -> None:
    msg = f"[SSH PAM CSO] Command denied by policy (mode={mode}, policy=v2).\n"
    os.write(sys.stdout.fileno(), msg.encode())
    subprocess.run(
        [
            "/usr/local/bin/pam-syslog.sh",
            "pam-deny",
            f"mode={mode} policy=v2 user={os.environ.get('USER', 'unknown')} "
            f"denied pattern={matched} cmd={line!r}",
        ],
        check=False,
    )


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
    stdout_fd = sys.stdout.fileno()
    saved_tty = prepare_parent_tty(stdin_fd)
    sync_winsize(stdin_fd, master_fd)
    stop_loop = False
    gate = LineGate(stdout_fd)
    csi_filter = StdinCsiFilter()
    code = 0

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

    def evaluate_and_forward(line: str, payload: bytes) -> bool:
        nonlocal code, stop_loop
        matched = deny_match(line, patterns) if patterns else None
        if matched:
            emit_deny(mode, matched, line)
            if kill_on_deny:
                os.kill(pid, signal.SIGTERM)
                code = 1
                stop_loop = True
            return False
        os.write(master_fd, payload)
        return True

    def handle_input_chunk(data: bytes) -> None:
        nonlocal stop_loop
        data = csi_filter.feed(data)
        if not data:
            return

        for paste in gate.feed_paste(data):
            for part in paste.splitlines():
                line = part.decode("utf-8", errors="replace")
                gate.local_echo(part + b"\n")
                evaluate_and_forward(line, part + b"\n")

        i = 0
        while i < len(data):
            if data.startswith(_BRACKETED_PASTE_START, i) or data.startswith(_BRACKETED_PASTE_END, i):
                marker = _BRACKETED_PASTE_START if data.startswith(_BRACKETED_PASTE_START, i) else _BRACKETED_PASTE_END
                gate.paste_buf.extend(data[i : i + len(marker)])
                i += len(marker)
                for paste in gate.feed_paste(b""):
                    for part in paste.splitlines():
                        line = part.decode("utf-8", errors="replace")
                        gate.local_echo(part + b"\n")
                        evaluate_and_forward(line, part + b"\n")
                continue

            byte = data[i]
            i += 1

            if byte == 0x03:
                gate.clear_buffer()
                os.write(master_fd, b"\x03")
                continue
            if byte in (8, 127):
                gate.local_backspace()
                continue
            if byte == 0x04:
                if not gate.line_buf:
                    stop_loop = True
                continue
            if byte in (10, 13):
                line, payload = gate.submit_line(byte)
                gate.local_echo(b"\n")
                if not evaluate_and_forward(line, payload):
                    return
                continue
            if byte == 0x1B:
                continue
            gate.append_printable(byte)

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
                    out_data = os.read(master_fd, 4096)
                except OSError:
                    break
                if not out_data:
                    break
                out_data = strip_cpr_output(out_data)
                if out_data:
                    os.write(stdout_fd, out_data)

            if stdin_fd in readable:
                try:
                    in_data = os.read(stdin_fd, 4096)
                except OSError as exc:
                    if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                        continue
                    in_data = b""
                if not in_data:
                    break
                handle_input_chunk(in_data)
                if stop_loop:
                    break

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
