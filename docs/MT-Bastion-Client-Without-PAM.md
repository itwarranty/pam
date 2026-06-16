# Первый контролируемый контур без PAM

**MT: Bastion Tier 3 (SSH Gateway)** — для организаций **200–1000 сотрудников**, преимущественно Linux, **без СКДПУ/PAM**, с договорным или регуляторным давлением на аудит доступа подрядчиков.

---

## Что получает заказчик

| Вопрос аудитора | Ответ с gateway |
|:---|:---|
| **Кто** подключался? | `operator` в `.meta`, JSONL `sessions.jsonl`, syslog `mt-bastion-gateway` |
| **Когда**? | UTC timestamp в sidecar и JSONL |
| **Куда** (target)? | `TARGET`, `TARGET_HOST`, `TARGET_ACCOUNT` в `.meta` |
| **Что** делал на сервере? | Полный PTY log `gateway_*.log` + `sha256sum -c` |
| **Как отозвать**? | Удалить из `bastion_operators` + `jit_purge`; kill — `bastion-session-ctl kill` |

---

## Режимы доступа

| Режим | Когда использовать | Запись на target |
|:---|:---|:---:|
| `jump` | Автomation, низкий риск, миграция | ❌ (connect-audit) |
| **`gateway`** | **Интерактивная поддержка prod** | ✅ |
| `shell` | Работа на бастионе / four-eyes | ✅ (bastion) |
| `audit` | Клиентский аудитор | read-only logs |

**Рекомендация CSO:** для prod Linux targets — `access: gateway`. Jump оставить только с `bastion_jump_approved: true`.

---

## Минимальный деплой (checklist)

1. Rocky Linux 9.x, SELinux Enforcing, Rootless Podman.
2. `./trusted_download.sh` → Air Gap transfer → `ansible-playbook site.yml`.
3. `bastion_targets[]` — inventory целей + ключи через **Ansible Vault** (не plaintext в git).
4. `bastion_operators[]` — `access: gateway`, `permit_open` ⊆ targets.
5. Post-deploy: `./scripts/bastion-compliance-verify.sh` exit 0.
6. Проверка: gateway session → log + `sha256sum -c` → `bastion-session-ctl list`.

---

## Формулировка для SoW / договора поддержки

> Доступ инженеров подрядчика к согласованному перечню Linux-серверов осуществляется **только** через MT: Bastion. Интерактивные сессии — в режиме **SSH gateway** с полной записью TTY на стороне заказчика, MFA, JIT-окнами и возможностью принудительного разрыва сессии (`bastion-session-ctl`).

---

## Ограничения Free tier (честно)

- Нет RDP/VNC/web/database протоколов.
- Нет self-service portal / ITSM API.
- Нет HA-кластера и центрального multi-tenant SaaS.
- Command denylist — best-effort (как shell policy).
- ФСТЭК / реестр — организационный трек, не продукт.

---

## Lab demo

```bash
./scripts/dev-up.sh
ssh -p 2222 -i lab/keys/gateway-lab.lab gateway-lab@127.0.0.1
# exit → verify log:
limactl shell mt-bastion-prod -- sudo ls /var/log/bastion_sessions/gateway_*
bastion-session-ctl list
```

Подробнее: [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) · [Whitepaper §4](./MT-Bastion-Whitepaper.md)

---

*MT Global — MT: Bastion Client Without PAM v1.0*
