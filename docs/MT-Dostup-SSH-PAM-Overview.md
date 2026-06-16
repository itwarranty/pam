# «МТ Доступ» — SSH PAM (обзор для заказчика)

**MT: Bastion** — open-source tier продукта **«МТ Доступ»**: полноценный **SSH-only PAM** (не урезанная «jump-only» версия). Запись сессий на target, credential broking, MFA, JIT, session kill, SIEM/JSONL — в одном Security-as-a-Code репозитории.

**Целевой сегмент:** организации **200–1000 сотрудников**, Linux-heavy, без СКДПУ или с поэтапной миграцией на gateway.

---

## Что получает заказчик

| Вопрос аудитора | Ответ |
|:---|:---|
| **Кто**? | operator в `.meta`, `sessions.jsonl`, `bastion-session-search` |
| **Когда**? | UTC в sidecar и JSONL |
| **Куда**? | `TARGET`, `TARGET_HOST` (gateway) |
| **Что** делал? | PTY log `gateway_*.log` + `sha256sum -c` |
| **Как отозвать**? | `bastion_operators` + `jit_purge`; `bastion-session-ctl kill` |

---

## Режимы SSH PAM

| `access` | Назначение | Запись на target |
|:---|:---|:---:|
| `jump` | ProxyJump, automation | ❌ connect-audit |
| **`gateway`** | **Prod интерактив** | ✅ |
| `shell` | Bastion / four-eyes | ✅ (bastion) |
| `audit` | Аудитор + live watch (Tier 4) | read-only |

---

## Минимальный деплой

1. Rocky Linux 9.x, SELinux Enforcing, Rootless Podman.
2. `./trusted_download.sh` → Air Gap → `ansible-playbook site.yml`.
3. `bastion_targets[]` + Vault keys; `bastion_operators[]` с `access: gateway`.
4. `./scripts/bastion-compliance-verify.sh` exit 0.
5. `bastion-session-search --operator X --since 7d` (Tier 4).

SoW: [MT-Bastion-SoW-SSH-Access.md](./MT-Bastion-SoW-SSH-Access.md) · Сравнение: [Battlecard СКДПУ](./MT-Bastion-Battlecard-SKDPU-SSH.md)

---

## Ограничения (честно)

- **Только SSH** — RDP/VNC/web/database в коммерческой линейке «МТ Доступ», не в этом repo.
- Нет SaaS control plane; HA active-passive — documented pattern (Tier 4).
- ФСТЭК / реестр — организационный трек.

---

*MT Global — МТ Доступ SSH PAM Overview v1.0*
