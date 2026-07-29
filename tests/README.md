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
