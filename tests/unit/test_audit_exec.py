#!/usr/bin/env python3
"""Unit tests for pam-audit-exec strict parser."""
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "build/files/pam-audit-exec.py"


def load_module():
    spec = importlib.util.spec_from_file_location("pam_audit_exec", MODULE)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["pam_audit_exec"] = mod
    spec.loader.exec_module(mod)
    return mod


class AuditExecTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        os.environ["PAM_AUDIT_LOG_DIR"] = self.tmp.name
        self.mod.AUDIT_DIR = self.tmp.name
        Path(self.tmp.name, "sample.log").write_text("hello\n", encoding="utf-8")

    def test_rejects_shell_injection(self):
        corpus = [
            "$(id)",
            "`id`",
            "cat ${HOME}/x",
            "cat a; rm -rf /",
            "cat a | wc",
            "cat a && id",
            "cat a > /tmp/x",
            "cat a < /etc/passwd",
            "cat *\n",
        ]
        for line in corpus:
            with self.subTest(line=line):
                with mock.patch.object(self.mod, "audit_syslog"):
                    rc = self.mod.execute_line(line)
                self.assertEqual(rc, 1, line)

    def test_allows_safe_cat(self):
        path = str(Path(self.tmp.name, "sample.log"))
        with mock.patch.object(self.mod, "audit_syslog"):
            with mock.patch.object(self.mod.subprocess, "run") as run:
                run.return_value.returncode = 0
                rc = self.mod.execute_line(f"cat {path}")
        self.assertEqual(rc, 0)
        argv = run.call_args[0][0]
        self.assertEqual(argv[0], "/bin/cat")
        self.assertTrue(
            os.path.realpath(argv[1]).startswith(os.path.realpath(self.tmp.name))
        )

    def test_rejects_path_outside_audit_dir(self):
        with mock.patch.object(self.mod, "audit_syslog"):
            rc = self.mod.execute_line("cat /etc/passwd")
        self.assertEqual(rc, 1)

    def test_tail_follow_denied(self):
        path = str(Path(self.tmp.name, "sample.log"))
        with mock.patch.object(self.mod, "audit_syslog"):
            rc = self.mod.execute_line(f"tail -f {path}")
        self.assertEqual(rc, 1)

    def test_rejects_symlink_escape(self):
        with tempfile.TemporaryDirectory() as outside_dir:
            outside = Path(outside_dir, "secret.log")
            outside.write_text("secret\n", encoding="utf-8")
            link = Path(self.tmp.name, "link.log")
            link.symlink_to(outside)
            with mock.patch.object(self.mod, "audit_syslog"):
                with mock.patch.object(self.mod.subprocess, "run") as run:
                    run.return_value.returncode = 0
                    rc = self.mod.execute_line(f"cat {link}")
            self.assertEqual(rc, 1)
            run.assert_not_called()

    def test_rejects_less_shell_escape_option(self):
        path = str(Path(self.tmp.name, "sample.log"))
        with mock.patch.object(self.mod, "audit_syslog"):
            rc = self.mod.execute_line(f"less +!sh -i {path}")
        self.assertEqual(rc, 1)

    def test_no_write_side_effect_on_deny(self):
        marker = Path(self.tmp.name, "marker")
        with mock.patch.object(self.mod, "audit_syslog"):
            rc = self.mod.execute_line("echo pwned > marker")
        self.assertEqual(rc, 1)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
