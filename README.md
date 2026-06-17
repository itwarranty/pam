# MT: Bastion

Open-source tier продукта **«МТ Доступ»** — **SSH PAM** (Privileged Access Management) для Rocky Linux 9: gateway, MFA, JIT, session recording, Security-as-a-Code (Rootless Podman, CSO Policy Gate).

## Quick start (dev)

```bash
./scripts/dev-up.sh
```

## Admin tools

```bash
# Тестовый доступ (Git + Bastion, onboarding + QR)
./scripts/test-repo-key.sh create <name> --bastion --apply
./scripts/test-repo-key.sh revoke <name> --apply      # declarative purge + restart
./scripts/test-repo-key.sh apply-dev

# Compliance verify (Tier 1 — post-deploy)
./scripts/bastion-compliance-verify.sh
./scripts/mt-dostup-doctor.sh engineer-jump   # lab: role, TOTP, ProxyJump hint
ansible-playbook -i inventory/local-lima.yml site.yml --tags verify_compliance

# Gateway session control (Tier 3)
bastion-session-ctl list
ansible-playbook -i inventory/local-lima.yml site.yml --tags session_kill -e bastion_session_kill_id=<id>

# Session search / watch (Tier 4)
bastion-session-search --operator engineer1 --since 7d
bastion-session-watch <session-id>

# Доступ по GitHub-аккаунту
./scripts/repo-access.sh grant <github_user>
./scripts/repo-access.sh revoke <github_user>
```

## Documentation

| Документ | Описание |
| :--- | :--- |
| [docs/README.md](docs/README.md) | Индекс документации |
| [Engineer Onboarding](docs/Engineer-Onboarding.md) | Доступ к repo + dev-стенд |
| [Whitepaper](docs/MT-Bastion-Whitepaper.md) | Техпаспорт для CSO |
| [Troubleshooting Workflow](docs/MT-Bastion-Troubleshooting-Workflow.md) | Регламент инцидента |
| [CSO Demo Runbook](docs/CSO-Demo-Runbook.md) | Пресейл demo |
| [МТ Доступ SSH PAM Overview](docs/MT-Dostup-SSH-PAM-Overview.md) | PAM positioning для заказчика |
| [FIDO Onboarding](docs/MT-Bastion-FIDO-Onboarding.md) | FIDO-sk + TOTP (Tier 5) |
| [Battlecard vs СКДПУ SSH](docs/MT-Bastion-Battlecard-SKDPU-SSH.md) | Пресейл сравнение |
| [HA Runbook](docs/MT-Bastion-HA-Runbook.md) | Active-passive failover |
| [OpenSpec specs](openspec/specs/) | GA specs Tier 1–4 |
| [OpenSpec archive](openspec/changes/archive/) | Completed change history |

## Prod deploy

1. Заполните `bastion_operators` в `group_vars/all.yml` (Vault).
2. Соберите образ: `./trusted_download.sh` → перенесите tar в Air Gap.
3. `ansible-galaxy collection install -r requirements.yml`
4. `ansible-playbook -i inventory/hosts.yml site.yml`

Отзыв доступа: удалите оператора из `bastion_operators` и перевыпустите плейбук (`purge_revoked_operators.yml`).

## Releases

| Tag | Content |
| :--- | :--- |
| `v0.2.0` | Tier 1 Phase A — compliance, tamper logs, source IP, SIEM |
| `v0.4.0` | Tier 1 Phase B + C — JIT, SSH User CA policy |
| `v0.5.0` | Tier 2 — incident naming, denylist, audit, rate limit, break-glass |
| `v0.6.0` | Tier 3 — SSH gateway, target recording, session-ctl |
| **`v1.0.0`** | **Tier 4 — SSH PAM GA:** search, policy v2, watch, Vault, OIDC examples, HA |
| **`v1.1.0`** | **Tier 5 — FIDO-Anchor MFA:** `ed25519-sk` + TOTP, JIT sk certs |

Tier 1–5 реализованы в репозитории. FIDO onboarding: [docs/MT-Bastion-FIDO-Onboarding.md](docs/MT-Bastion-FIDO-Onboarding.md).

## CI

GitHub Actions: syntax-check `site.yml` (`.github/workflows/ci.yml`).
