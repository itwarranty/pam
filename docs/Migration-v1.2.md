# Migration guide — v1.2.0 security hardening

Applies when upgrading from v1.1.x to **v1.2.0** (OpenSpec `2026-08-pam-security-hardening`).

## Summary

| Area | v1.1.x | v1.2.0 |
| :--- | :--- | :--- |
| Audit role | shell `eval` | strict argv executor (`pam-audit-exec.py`) |
| Command policy | v1 optional on target | **v2 line-gate** on gateway PTY (default prod) |
| Session kill | single PID | process group (`pgid` in registry schema v2) |
| MFA deploy | could regenerate TOTP | preserves deployed secret unless rotate/bootstrap |
| Container deploy | `recreate: true` | convergent; **blocks** on active sessions |
| Audit logs (prod) | world-writable lab modes | `0640` files, `pam-audit` reader group |

## Session registry schema v2

New sessions write JSON with `schema: 2`, `pid`, and `pgid`.

- **Kill** uses `kill -TERM -<pgid>` then optional `KILL`.
- **Schema 1** records still work with a compatibility warning; they are replaced on the next session for the same operator.

No manual migration is required — old registry files are ignored when the process is gone (deploy precheck purges stale entries).

## Command policy v1 waiver

Target-side v1 (`bash --rcfile` denylist) is **migration-only**:

```yaml
pam_command_policy_v1_waiver: true   # temporary only
```

Production preflight fails if v2 is disabled without waiver.

**Removal target:** v1.3.0 (**2026-12-01**). Plan migration to v2 before that date.

## MFA secret lifecycle

| Flag | Purpose |
| :--- | :--- |
| `pam_mfa_bootstrap_generate: true` | Lab/eval only — generate once when no secret exists |
| `pam_mfa_rotate_operators: [name, ...]` | Explicit rotation — only listed operators get new TOTP |

Production: provide `operator.mfa_secret` from Vault or preserve existing `.google_authenticator`. Missing source → **fail-closed** preflight.

Rotate an operator:

```bash
ansible-playbook -i inventory/prod.yml site.yml \
  -e '{"pam_mfa_rotate_operators": ["ivanov_ia"]}'
```

Redistribute onboarding / TOTP out-of-band after rotation.

## Deploy during live sessions

Default: playbook **aborts** if gateway sessions are active (`pam_deploy_disrupt_active_sessions: false`).

Emergency override (logged):

```yaml
pam_deploy_disrupt_active_sessions: true
```

## Audit log permissions

Production profile (`group_vars/profiles/prod.yml`):

- Directory: `0750` `pam:pam-audit`
- `gateway.syslog`, `sessions.jsonl`: `0640`

Lab (`group_vars/dev/gateway_lab.yml`) may use relaxed modes for CSO demos — not for production.

## Verification after upgrade

On the gateway host:

```bash
./scripts/pam verify
./scripts/test-security-hardening.sh
python3 -m unittest discover -s tests/unit -p 'test_*.py' -v
```

Second Ansible pass should report `changed=0` (idempotent deploy).

## Related

- [CHANGELOG](../CHANGELOG.md) — v1.2.0
- [Integrations](./Integrations.md) — DR / RISK boundaries
- [Runbooks](./Runbooks.md) — session kill, live watch
