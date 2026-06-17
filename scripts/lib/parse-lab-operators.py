#!/usr/bin/env python3
"""Parse bastion_operators_* lists from group_vars/dev/*.yml (stdlib only)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

OPERATOR_START = re.compile(r"^\s+-\s+name:\s*(\S+)\s*$")
FIELD = re.compile(r"^\s+(mfa_secret|access|email|incident_id):\s*\"?([^\"#\n]+?)\"?\s*$")
PERMIT_ITEM = re.compile(r"^\s+-\s+\"?([^\"#\n]+?)\"?\s*$")
LIST_START = re.compile(r"^bastion_operators_\w+:\s*$")


def parse_file(path: Path) -> list[dict]:
    ops: list[dict] = []
    current: dict | None = None
    in_list = False
    in_permit = False

    for line in path.read_text(encoding="utf-8").splitlines():
        if LIST_START.match(line):
            in_list = True
            continue
        if in_list and line and not line.startswith(" ") and not line.startswith("#"):
            in_list = False
            in_permit = False
        if not in_list:
            continue

        m = OPERATOR_START.match(line)
        if m:
            if current:
                ops.append(current)
            current = {"name": m.group(1), "permit_open": [], "source": path.name}
            in_permit = False
            continue
        if not current:
            continue

        if re.match(r"^\s+permit_open:\s*$", line):
            in_permit = True
            continue
        if in_permit:
            pm = PERMIT_ITEM.match(line)
            if pm:
                current["permit_open"].append(pm.group(1).strip())
                continue
            if line.strip() and not line.startswith(" " * 4 + "-"):
                in_permit = False

        fm = FIELD.match(line)
        if fm:
            current[fm.group(1)] = fm.group(2).strip()

    if current:
        ops.append(current)
    return ops


def main() -> int:
    dev_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("group_vars/dev")
    by_name: dict[str, dict] = {}
    for yml in sorted(dev_dir.glob("*.yml")):
        for op in parse_file(yml):
            by_name[op["name"]] = op
    print(json.dumps(list(by_name.values()), indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
