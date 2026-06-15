# Документация MT: Bastion

Бесплатная версия продукта **«МТ Доступ»** — контролируемый SSH-бастion для удалённой поддержки в Air Gap / КИИ контурах.

| Документ | Аудитория | Назначение |
| :--- | :--- | :--- |
| [MT-Bastion-Whitepaper.md](./MT-Bastion-Whitepaper.md) | CSO, аудитор | Техпаспорт, Control Matrix, checklist |
| [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md) | ИБ + инженеры | Регламент инцидента, four-eyes, JIT |
| [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) | Пресейл | 10-мин демо на lab-стенде |
| [Engineer-Onboarding.md](./Engineer-Onboarding.md) | Инженеры MT Global | Git-доступ, dev-up, первый SSH |

## Платформа

Rocky Linux 9.x · x86_64 · SELinux Enforcing · Rootless Podman · firewalld

## Быстрый старт

```bash
./scripts/dev-up.sh
```

## Ключевые механизмы (код)

| Механизм | Где в коде |
| :--- | :--- |
| Policy Gate (preflight) | `tasks/preflight_cso.yml` |
| Jump без shell | `templates/authorized_keys.j2` (`restrict,port-forwarding`) |
| MFA strict | `build/Containerfile`, `tasks/verify_image_cso.yml` |
| Declarative revoke | `tasks/purge_revoked_operators.yml` |
| Hot reload | handler `Restart ssh bastion container` в `site.yml` |
| SELinux `container_file_t` | `tasks/provision_operator_item.yml` |
| Compliance verify (Tier 1) | `scripts/bastion-compliance-verify.sh`, tag `verify_compliance` |
| JIT access windows | `tasks/jit_filter_operators.yml`, `--tags jit_purge`, `configure_jit_timer.yml` |
| SSH User CA prod policy | `bastion_allow_raw_pubkey_prod`, `scripts/sign-operator-cert.sh.example` |
| Source IP / SIEM / WORM (Tier 1) | `tasks/configure_source_firewall.yml`, `configure_rsyslog_siem.yml`, `archive_session_logs_worm.yml` |
| Tamper-evident logs | `build/files/bastion-shell-wrapper.sh` (`.sha256` + `.meta`) |

## Спеки (OpenSpec)

| Change | Содержание |
| :--- | :--- |
| [openspec/specs/](../openspec/specs/) | **Tier 1 Free (GA):** compliance, JIT, SIEM, source IP, tamper logs, SSH User CA |
| [archive/2026-06-bastion-free-tier1-cso](../openspec/changes/archive/2026-06-bastion-free-tier1-cso/) | История change Tier 1 |
| [archive/2026-06-ssh-user-ca-qa-mtglobal](../openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/) | SSH User CA QA (live PKI pending) |
