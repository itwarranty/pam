# Локальное тестирование

Prod-parity VM (Rocky Linux 9, SELinux Enforcing) + lab-операторы из `group_vars/dev/`.

```bash
./scripts/dev-up.sh
```

Ручной путь:

```bash
./trusted_download.sh
./tests/start-lima.sh              # Lima instance: pam-prod
./tests/sync-artifacts.sh          # при необходимости
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/local-lima.yml site.yml
```

Документация: [docs/Engineer-Onboarding.md](../docs/Engineer-Onboarding.md), [docs/CSO-Demo-Runbook.md](../docs/CSO-Demo-Runbook.md)

## Security hardening acceptance (v1.2+)

On the Rocky gateway host or `limactl shell pam-prod`:

```bash
./scripts/test-security-hardening.sh
python3 -m unittest discover -s tests/unit -p 'test_*.py' -v
./scripts/check-doc-naming.sh
```

Individual checks: `test-audit-exec-container.sh`, `test-pty-linegate.sh`, `test-session-pgid-kill.sh`, `test-session-watch-auth.sh`, `test-mfa-preserve.sh`, `test-mfa-rotate.sh` (optional: `SKIP_MFA_ROTATE=0`), `test-audit-log-perms.sh`, `test-prod-audit-modes.sh`, `test-deploy-active-session-block.sh`, `test-pam-verify-json.sh`. Full playbook block: `PAM_DEPLOY_BLOCK_FULL=1 ./scripts/test-deploy-active-session-block.sh`.

Static: `./scripts/check-shell.sh` (requires shellcheck).

CI also runs `./scripts/check-runbook-commands.sh` and `./scripts/check-doc-naming.sh`.

Migration notes: [docs/Migration-v1.2.md](../docs/Migration-v1.2.md).

Two-pass idempotence (slow, ~2× full playbook):

```bash
./scripts/test-ansible-idempotence.sh inventory/local-lima.yml
```
