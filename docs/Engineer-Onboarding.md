# Onboarding инженера MT: Bastion

Репозиторий **private**: `git@github.com:MT-Global-Team/mt-bastion.git`

**Связанные документы:** [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) · [Whitepaper](./MT-Bastion-Whitepaper.md) · [Workflow](./MT-Bastion-Troubleshooting-Workflow.md)

---

## Часть A. Для администратора (выдача доступа)

### Тестовый доступ — один ключ на Git + Bastion

**Prerequisite (org owner):** Deploy keys → Enabled в Member privileges.  
**Prerequisite (admin):** Node.js — QR в onboarding (`npm install` в `scripts/`, автоматически).

```bash
cd mt-bastion

# Полный цикл: ключ + YAML + bastion (одна команда)
./scripts/test-repo-key.sh create tester-01 --bastion --apply

# Отзыв: GitHub + YAML + purge на bastion + restart контейнера
./scripts/test-repo-key.sh revoke tester-01 --apply

# Или вручную применить после create/revoke
./scripts/test-repo-key.sh apply-dev

./scripts/test-repo-key.sh list
./scripts/test-repo-key.sh onboarding tester-01
```

Передать тестировщику каталог **`~/.mt-bastion/test-access/<name>/`**:

| Файл | Назначение |
|:---|:---|
| `<name>.key` | private key |
| `<name>.onboarding.txt` | ssh config, TOTP, ASCII QR |
| `<name>.totp.png` | QR для Authenticator |

**Declarative sync:** `group_vars/dev/test_operators.yml` → Ansible удаляет операторов вне списка, перезапускает контейнер.

Только Git: `./scripts/test-repo-key.sh create tester-01` (без `--bastion`).

### Read-only по GitHub-аккаунту (без отдельного ключа)

```bash
./scripts/repo-access.sh grant GITHUB_USERNAME
./scripts/repo-access.sh revoke GITHUB_USERNAME
```

Инженер клонирует своим SSH-ключом из GitHub Settings.

### Write — team `bastion-engineers`

https://github.com/orgs/MT-Global-Team/teams/bastion-engineers

**Добавить инженера:** Members → Add member (пользователь должен быть в org MT-Global-Team).

### Альтернатива — collaborator

https://github.com/MT-Global-Team/mt-bastion → Settings → Collaborators — Read или Write.

### Что не передавать инженерам

- Prod-секреты (`group_vars/all.yml`, Ansible Vault)
- Private SSH User CA — см. `openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/`
- Prod TOTP из `generated/mfa/`

---

## Часть B. Для инженера (первый запуск)

### 1. SSH-ключ GitHub

```bash
ssh-keygen -t ed25519 -C "you@mtglobal.team"
cat ~/.ssh/id_ed25519.pub
```

https://github.com/settings/ssh-keys

### 2. Clone

```bash
git clone git@github.com:MT-Global-Team/mt-bastion.git
cd mt-bastion
```

### 3. Зависимости (macOS)

```bash
brew install lima podman ansible
```

### 4. Dev-стенд (Rocky 9 x86_64 в Lima)

```bash
./scripts/dev-up.sh
```

Скрипт выполняет:

1. `lab/keys/*.lab` (jump, shell, gateway, audit, break-glass — при отсутствии)
2. Lima VM `mt-bastion-prod` (`./tests/start-lima.sh`)
3. Сборку/синхронизацию образа (`trusted_download.sh`, `tests/sync-artifacts.sh`)
4. `ansible-playbook -i inventory/local-lima.yml site.yml`

**Конфигурация lab** (не prod):

| Файл | Назначение |
| :--- | :--- |
| `group_vars/dev/lab.yml` | Базовые операторы jump/shell |
| `group_vars/dev/gateway_lab.yml` | `gateway-lab`, mock target |
| `group_vars/dev/audit_lab.yml`, `break_glass_lab.yml` | audit / break-glass |
| `group_vars/dev/operators_merge.yml` | Слияние всех lab-операторов |
| `group_vars/local_lima.yml` | Путь к tar на Lima |
| `inventory/local-lima.yml` | Host `mt-bastion-lima` через Lima SSH |

### 5. Проверка SSH к бастion-контейнеру

```bash
ssh -p 2222 -i lab/keys/gateway-lab.lab gateway-lab@127.0.0.1
ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1
ssh -p 2222 -i lab/keys/engineer-shell.lab engineer-shell@127.0.0.1
```

TOTP: otpauth URI в комментариях `group_vars/dev/lab.yml`.

**Jump:** прямой shell отклонён (`restrict,port-forwarding`).  
**Gateway:** интерактив на mock target; лог `gateway_*` на хосте.  
**Shell:** PTY + лог в `/var/log/bastion_sessions/`.

### 6. Сценарии для отчёта

[CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md)

---

## Часть C. Работа с кодом

| Действие | Команда |
| :--- | :--- |
| Обновить repo | `git pull` |
| Новая фича | `git checkout -b feature/...` → PR в `main` |
| Синтаксис playbook | `ansible-playbook --syntax-check -i inventory/local-lima.yml site.yml` |
| Lab doctor (роль, TOTP, команда) | `./scripts/mt-dostup-doctor.sh engineer-jump` |
| Lab-образ с nullok (только dev) | `BASTION_LAB_MODE=1 MFA_STRICT=0 ./trusted_download.sh` |
| Пересборка после Tier 2/3/4 scripts | `./trusted_download.sh` (wrapper, gateway, pty-inspector) → redeploy |

## Tier 4 (v1.0 GA)

| CLI | Назначение |
| :--- | :--- |
| `bastion-session-search` | Поиск сессий в JSONL |
| `bastion-session-watch` | Live moderation gateway log |
| `bastion-ha-promote.sh` | Failover standby → primary |

OpenSpec: `openspec/changes/archive/2026-06-bastion-free-tier4-ssh-pam-complete/`

Prod profile: `group_vars/prod.yml.example`

Prod-деплой (`inventory/hosts.yml` + Vault + Rocky 9) — только по согласованию с lead / CSO.

## Tier 5 — FIDO-Anchor MFA (v1.1)

| Действие | Команда / документ |
| :--- | :--- |
| Onboarding | [MT-Bastion-FIDO-Onboarding.md](./MT-Bastion-FIDO-Onboarding.md) |
| Lab FIDO operator | `BASTION_FIDO_LAB=1 ./scripts/dev-up.sh` |
| Preflight check | `python3 scripts/preflight-fido-key.py < test/fixtures/fido-pubkey.txt` |
| JIT cert (sk) | `scripts/sign-operator-cert-jit.sh.example` |
| Prod vars | `bastion_require_fido_pubkey: true`, `bastion_mfa_mode: fido_totp` |

Dev lab по умолчанию: `bastion_require_fido_pubkey: false` — `.lab` keys без изменений.

---

## Troubleshooting

- Инциденты и four-eyes: [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md)
- Command denylist: см. Workflow §5.4; проверьте `bastion_shell_command_policy_enabled` и mount `/etc/bastion/command_denylist`
- Break-glass: см. Workflow §5.5; preflight требует `incident_id`, `valid_until`, окно ≤ `bastion_break_glass_max_hours`
- Lima VM: `tests/README.md`, `limactl shell mt-bastion-prod`
- Preflight fail: проверьте Rocky 9, Enforcing, whitelist, `bastion_operators`

---

*MT Global — Engineer Onboarding v1.5*
