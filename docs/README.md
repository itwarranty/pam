# Документация MT: Bastion

Бесплатная версия продукта **«МТ Доступ»** — контролируемый SSH-бастion для удалённой поддержки в Air Gap / КИИ контурах.

| Документ | Аудитория | Назначение |
| :--- | :--- | :--- |
| [MT-Bastion-Whitepaper.md](./MT-Bastion-Whitepaper.md) | CSO, аудитор | Техпаспорт, Control Matrix, checklist |
| [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md) | ИБ + инженеры | Регламент инцидента, four-eyes, JIT |
| [MT-Bastion-Client-Without-PAM.md](./MT-Bastion-Client-Without-PAM.md) | CSO, заказчик | Tier 3: первый контур без PAM |
| [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) | Пресейл | Demo lab (Tier 1–3) |
| [Engineer-Onboarding.md](./Engineer-Onboarding.md) | Инженеры MT Global | Git-доступ, dev-up, первый SSH |

## Версии (Tier 1–3 Free)

| Tag | Содержание |
| :--- | :--- |
| [v0.2.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.2.0) | Tier 1 Phase A |
| [v0.4.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.4.0) | Tier 1 Phase B + C |
| [v0.5.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.5.0) | Tier 2 |
| [v0.6.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.6.0) | Tier 3 SSH Gateway (текущий) |

**Tier 1–3 реализованы в репозитории.**

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
| SSH gateway (Tier 3) | `access: gateway`, `bastion_targets`, `bastion-ssh-gateway-wrapper.sh` |
| Session control (Tier 3) | `bastion-session-ctl`, JIT kill, JSONL export |

## Спеки (OpenSpec)

| Change | Содержание |
| :--- | :--- |
| [openspec/specs/](../openspec/specs/) | **Tier 1–3 GA** |
| [archive/2026-06-bastion-ssh-gateway-tier3](../openspec/changes/archive/2026-06-bastion-ssh-gateway-tier3/) | История change Tier 3 |
| [archive/2026-06-ssh-user-ca-qa-mtglobal](../openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/) | SSH User CA QA (live PKI pending) |
