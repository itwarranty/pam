# MT: Bastion

Бесплатная open-source версия **«МТ Доступ»** — Security-as-a-Code jump host для Rocky Linux 9 (Rootless Podman, CSO Policy Gate).

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
| [CSO Demo Runbook](docs/CSO-Demo-Runbook.md) | 10-мин пресейл |
| [OpenSpec: SSH User CA QA](openspec/changes/ssh-user-ca-qa-mtglobal/) | QA user certificates |

## Prod deploy

1. Заполните `bastion_operators` в `group_vars/all.yml` (Vault).
2. Соберите образ: `./trusted_download.sh` → перенесите tar в Air Gap.
3. `ansible-galaxy collection install -r requirements.yml`
4. `ansible-playbook -i inventory/hosts.yml site.yml`

Отзыв доступа: удалите оператора из `bastion_operators` и перевыпустите плейбук (`purge_revoked_operators.yml`).

## CI

GitHub Actions: syntax-check `site.yml` (`.github/workflows/ci.yml`).
