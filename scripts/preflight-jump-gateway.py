#!/usr/bin/env python3
"""Preflight: jump vs gateway CSO policy (Tier 3). Exit 0 pass, 1 fail."""
import json
import os
import sys

operators = json.loads(os.environ.get("OPERATORS", "[]"))
targets = json.loads(os.environ.get("TARGETS", "[]"))
prod_require = os.environ.get("PROD_REQUIRE_GATEWAY", "false") == "true"
prod_tags = set(json.loads(os.environ.get("PROD_TAGS", '["prod"]')))
jump_risk = os.environ.get("JUMP_RISK", "false") == "true"

index = {}
for t in targets:
    port = t.get("port", 22)
    hp = f"{t['host']}:{port}"
    index[hp] = t

errors = []
for op in operators:
    access = op.get("access", "jump")
    name = op.get("name", "?")
    approved = op.get("bastion_jump_approved", False)

    if jump_risk and access == "jump" and not approved:
        errors.append(
            f"Operator {name} (jump): bastion_jump_approved required (connect-audit only)"
        )

    if not prod_require:
        continue

    permits = op.get("permit_open") or []
    for entry in permits:
        tgt = index.get(entry)
        if not tgt:
            continue
        tags = set(tgt.get("tags") or [])
        if not tags.intersection(prod_tags):
            continue
        if access == "jump" and not approved:
            errors.append(
                f"Operator {name}: jump on prod target {entry} — use gateway or bastion_jump_approved"
            )
        elif access != "gateway" and access != "jump":
            errors.append(
                f"Operator {name}: prod target {entry} requires access: gateway"
            )

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
sys.exit(0)
