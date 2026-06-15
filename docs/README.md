# Документация MT: Bastion

Бесплатная версия продукта **«МТ Доступ»** — контролируемый SSH-бастion для удалённой поддержки в Air Gap / КИИ контурах.

| Документ | Аудитория | Назначение |
| :--- | :--- | :--- |
| [MT-Bastion-Whitepaper.md](./MT-Bastion-Whitepaper.md) | CSO, аудитор | Техпаспорт, Control Matrix, checklist |
| [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md) | ИБ + инженеры | Регламент инцидента, four-eyes, JIT |
| [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) | Пресейл | 15-мин демо на lab-стенде (Tier 1 + Tier 2) |
| [Engineer-Onboarding.md](./Engineer-Onboarding.md) | Инженеры MT Global | Git-доступ, dev-up, первый SSH |

## Версии (Tier 1 + Tier 2 Free)

| Tag | Содержание |
| :--- | :--- |
| [v0.2.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.2.0) | Tier 1 Phase A |
| [v0.4.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.4.0) | Tier 1 Phase B + C |
| [v0.5.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.5.0) | Tier 2 Phases A–E (текущий) |

Подробнее: [Whitepaper §Версии релиза](./MT-Bastion-Whitepaper.md), [openspec/changes/archive/README.md](../openspec/changes/archive/README.md).

**В репозитории Tier 1 и Tier 2 Free реализованы полностью.** Live PKI QA и prod GA certificates — после org sign-off (`bastion_ssh_user_ca_qa_complete`).

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
| Incident log naming (Tier 2) | `incident_id` в basename session log |
| Shell command denylist (Tier 2) | `bastion-command-policy.sh`, `configure_shell_command_policy.yml` |
| Audit readonly role (Tier 2) | `access: audit`, `bastion-audit-shell-wrapper.sh` |
| SSH rate limit (Tier 2) | `configure_ssh_brute_force.yml` |
| Break-glass (Tier 2) | `break_glass: true`, preflight, auditd key |

## Спеки (OpenSpec)

| Change | Содержание |
| :--- | :--- |
| [openspec/specs/](../openspec/specs/) | **Tier 1 + Tier 2 Free (GA):** compliance, JIT, SIEM, command policy, audit, rate limit, break-glass |
| [archive/2026-06-bastion-free-tier1-cso](../openspec/changes/archive/2026-06-bastion-free-tier1-cso/) | История change Tier 1 |
| [archive/2026-06-bastion-free-tier2-cso](../openspec/changes/archive/2026-06-bastion-free-tier2-cso/) | История change Tier 2 |
| [archive/2026-06-ssh-user-ca-qa-mtglobal](../openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/) | SSH User CA QA (live PKI pending) |
