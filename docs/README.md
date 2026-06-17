# Документация «МТ Доступ» (MT: Bastion)

Open-source tier продукта **«МТ Доступ»** — полноценный **SSH PAM** (Privileged Access Management) в модели Security-as-a-Code для Air Gap / КИИ.

| Документ | Аудитория | Назначение |
| :--- | :--- | :--- |
| [MT-Bastion-Whitepaper.md](./MT-Bastion-Whitepaper.md) | CSO, аудитор | Техпаспорт, Policy Gate, checklist |
| [MT-Dostup-SSH-PAM-Overview.md](./MT-Dostup-SSH-PAM-Overview.md) | CSO, заказчик | Обзор SSH PAM для заказчика |
| [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md) | ИБ + инженеры | Регламент инцидента, four-eyes, JIT |
| [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) | Пресейл | Demo lab (Tier 1–4) |
| [MT-Bastion-Battlecard-SKDPU-SSH.md](./MT-Bastion-Battlecard-SKDPU-SSH.md) | Пресейл | Сравнение с СКДПУ SSH |
| [MT-Bastion-SoW-SSH-Access.md](./MT-Bastion-SoW-SSH-Access.md) | Юристы | Формулировка для договора |
| [MT-Bastion-HA-Runbook.md](./MT-Bastion-HA-Runbook.md) | SRE | Active-passive HA |
| [MT-Bastion-FIDO-Onboarding.md](./MT-Bastion-FIDO-Onboarding.md) | CSO, операторы | FIDO-sk + TOTP (Tier 5) |
| [Engineer-Onboarding.md](./Engineer-Onboarding.md) | Инженеры MT Global | Git-доступ, dev-up, первый SSH |

## Релизы

| Tag | Содержание |
| :--- | :--- |
| [v0.2.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.2.0) | Tier 1 Phase A |
| [v0.4.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.4.0) | Tier 1 Phase B + C |
| [v0.5.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.5.0) | Tier 2 |
| [v0.6.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v0.6.0) | Tier 3 SSH Gateway |
| **[v1.0.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v1.0.0)** | Tier 4 SSH PAM GA |
| **[v1.1.0](https://github.com/MT-Global-Team/mt-bastion/releases/tag/v1.1.0)** | **Tier 5 FIDO-Anchor MFA (текущий)** |

Tier 1–5 реализованы в репозитории. Полный перечень контролей — Policy Gate в [Whitepaper](./MT-Bastion-Whitepaper.md).

## Платформа

Rocky Linux 9.x · x86_64 · SELinux Enforcing · Rootless Podman · firewalld

## Быстрый старт

```bash
./scripts/dev-up.sh
```

## Точки входа в код

| Область | Пути |
| :--- | :--- |
| Deploy | `site.yml`, `tasks/preflight_cso.yml` |
| Gateway / targets | `build/files/bastion-ssh-gateway-*.sh`, `tasks/provision_bastion_targets.yml` |
| Session CLI | `scripts/bastion-session-{ctl,search,watch}.sh` |
| Compliance | `scripts/bastion-compliance-verify.sh` |
| FIDO policy | `scripts/preflight-fido-key.py`, `tasks/preflight_fido_operators.yml` |
| Policy | `group_vars/all.yml`, `templates/sshd_config.j2` |

## OpenSpec

| Путь | Содержание |
| :--- | :--- |
| [openspec/specs/](../openspec/specs/) | GA Tier 1–5 |
| [archive/2026-06-bastion-fido-anchor-mfa](../openspec/changes/archive/2026-06-bastion-fido-anchor-mfa/) | История change Tier 5 |
| [archive/2026-06-bastion-free-tier4-ssh-pam-complete](../openspec/changes/archive/2026-06-bastion-free-tier4-ssh-pam-complete/) | История change Tier 4 |
| [archive/2026-06-ssh-user-ca-qa-mtglobal](../openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/) | SSH User CA QA (live PKI pending) |
