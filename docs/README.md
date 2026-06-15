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

## Спеки

OpenSpec: `../openspec/` — SSH User CA QA и др.
