# SSH PAM — обзор для заказчика

**SSH PAM** — white-label **SSH-only PAM**: запись сессий на target, credential broking, MFA (FIDO + TOTP), JIT, session kill, SIEM/JSONL — Security-as-a-Code.

**Текущий релиз:** [v1.1.0](https://github.com/itwarranty/itwarranty-pam/releases/tag/v1.1.0) (Tier 5 FIDO-Anchor MFA).

**Целевой сегмент:** организации **200–1000 сотрудников**, Linux-heavy; замена или миграция с коммерческого SSH PAM (СКДПУ и аналоги).

---

## Что получает заказчик

| Вопрос аудитора | Ответ |
|:---|:---|
| **Кто**? | operator в `.meta`, `sessions.jsonl`, `bastion-session-search` |
| **Когда**? | UTC в sidecar и JSONL |
| **Куда**? | `TARGET`, `TARGET_HOST` (gateway) |
| **Что** делал? | PTY log `gateway_*.log` + `sha256sum -c` |
| **Как отозвать**? | `bastion_operators` + `jit_purge`; `bastion-session-ctl kill` |
| **MFA**? | FIDO-sk на ноутбуке + offline TOTP на шлюз (prod) |

---

## Режимы SSH PAM

| `access` | Назначение | Запись на target |
|:---|:---|:---:|
| `jump` | ProxyJump, automation | ❌ connect-audit |
| **`gateway`** | **Prod интерактив** | ✅ |
| `shell` | Gateway / four-eyes | ✅ (bastion) |
| `audit` | Аудитор + live watch | read-only |

---

## Минимальный деплой

1. Rocky Linux 9.x, SELinux Enforcing, Rootless Podman.
2. `./trusted_download.sh` → Air Gap → `ansible-playbook site.yml`.
3. `bastion_targets[]` + Vault keys; `bastion_operators[]` с `access: gateway`.
4. Prod MFA: `bastion_require_fido_pubkey: true`, `bastion_mfa_mode: fido_totp` — см. [FIDO Onboarding](./FIDO-Onboarding.md).
5. `./scripts/bastion-compliance-verify.sh` exit 0.
6. `bastion-session-search --operator X --since 7d`.

Детали: [Whitepaper](./Whitepaper.md) · SoW: [SoW-SSH-Access.md](./SoW-SSH-Access.md) · Сравнение: [Battlecard](./Battlecard-SKDPU-SSH.md)

---

## Ограничения (честно)

- **Только SSH** — RDP/VNC/web/database в коммерческой линейке, не в этом repo.
- Нет SaaS control plane; HA — [HA-Runbook.md](./HA-Runbook.md) (opt-in).
- ФСТЭК / реестр — организационный трек.

---

*SSH PAM Overview v1.1*
