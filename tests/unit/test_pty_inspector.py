#!/usr/bin/env python3
"""Unit tests for PTY inspector denylist and line gate."""
import importlib.util
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "build/files/pam-pty-inspector.py"


def load_module():
    spec = importlib.util.spec_from_file_location("pam_pty_inspector", MODULE)
    mod = importlib.util.module_from_spec(spec)
    import sys
    sys.modules["pam_pty_inspector"] = mod
    spec.loader.exec_module(mod)
    return mod


class PtyInspectorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_deny_match(self):
        patterns = self.mod.load_patterns(str(ROOT / "tests/fixtures/denylist.txt"))
        self.assertTrue(self.mod.deny_match("rm -rf /", patterns))

    def test_csi_filter_drops_cpr(self):
        filt = self.mod.StdinCsiFilter()
        out = filt.feed(b"hello\x1b[21;17Rworld")
        self.assertEqual(out, b"helloworld")

    def test_line_gate_local_echo_and_submit(self):
        gate = self.mod.LineGate(1)
        with mock.patch("os.write") as write:
            gate.append_printable(ord("a"))
            line, payload = gate.submit_line(10)
        self.assertEqual(line, "a")
        self.assertEqual(payload, b"a\n")

    def test_bracketed_paste_splits_lines(self):
        gate = self.mod.LineGate(1)
        chunk = (
            b"\x1b[200~ls -la\nrm -rf /\x1b[201~"
        )
        lines = []
        for paste in gate.feed_paste(chunk):
            lines.extend(paste.splitlines())
        self.assertEqual(lines, [b"ls -la", b"rm -rf /"])

    def test_bracketed_paste_denylist_per_line(self):
        patterns = self.mod.load_patterns(str(ROOT / "tests/fixtures/denylist.txt"))
        gate = self.mod.LineGate(1)
        chunk = b"\x1b[200~echo ok\nrm -rf /\x1b[201~"
        denied = []
        allowed = []
        for paste in gate.feed_paste(chunk):
            for part in paste.splitlines():
                line = part.decode("utf-8", errors="replace")
                if self.mod.deny_match(line, patterns):
                    denied.append(line)
                else:
                    allowed.append(line)
        self.assertEqual(allowed, ["echo ok"])
        self.assertEqual(denied, ["rm -rf /"])


if __name__ == "__main__":
    unittest.main()
