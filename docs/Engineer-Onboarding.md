# Onboarding инженера SSH PAM

Репозиторий **private**: `git@github.com:itwarranty/pam.git`

**Связанные документы:** [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md) · [Whitepaper](./Whitepaper.md) · [Workflow](./Troubleshooting-Workflow.md)

---

## Часть A. Для администратора (выдача доступа)

### Тестовый доступ — один ключ на Git + gateway

**Prerequisite (org owner):** Deploy keys → Enabled в Member privileges.  
**Prerequisite (admin):** Node.js — QR в onboarding (`npm install` в `scripts/`, автоматически).

```bash
cd pam

# Полный цикл: ключ + YAML + gateway (одна команда)
./scripts/test-repo-key.sh create tester-01 --pam --apply

# Отзыв: GitHub + YAML + purge на шлюзе + restart контейнера
./scripts/test-repo-key.sh revoke tester-01 --apply

# Или вручную применить после create/revoke
./scripts/test-repo-key.sh apply-dev

./scripts/test-repo-key.sh list
./scripts/test-repo-key.sh onboarding tester-01
```

Передать тестировщику каталог **`~/.itwarranty-pam/test-access/<name>/`**:

| Файл | Назначение |
|:---|:---|
| `<name>.key` | private key |
| `<name>.onboarding.txt` | ssh config, TOTP, ASCII QR |
| `<name>.totp.png` | QR для Authenticator |

**Declarative sync:** `group_vars/dev/test_operators.yml` → Ansible удаляет операторов вне списка, перезапускает контейнер.

Только Git: `./scripts/test-repo-key.sh create tester-01` (без `--pam`).

### Read-only по GitHub-аккаунту (без отдельного ключа)

```bash
./scripts/repo-access.sh grant GITHUB_USERNAME
./scripts/repo-access.sh revoke GITHUB_USERNAME
```

Инженер клонирует своим SSH-ключом из GitHub Settings.

### Write — team `itwarranty-engineers`

https://github.com/orgs/itwarranty/teams/itwarranty-engineers

**Добавить инженера:** Members → Add member (пользователь должен быть в org itwarranty).

### Альтернатива — collaborator

https://github.com/itwarranty/pam → Settings → Collaborators — Read или Write.

### Что не передавать инженерам

- Prod-секреты (`group_vars/all.yml`, Ansible Vault)
- Private SSH User CA — см. `openspec/changes/archive/2026-06-ssh-user-ca-qa/`
- Prod TOTP из `generated/mfa/`

---

## Часть B. Для инженера (первый запуск)

### 1. SSH-ключ GitHub

```bash
ssh-keygen -t ed25519 -C "you@example.com"
cat ~/.ssh/id_ed25519.pub
```

https://github.com/settings/ssh-keys

### 2. Clone

```bash
git clone git@github.com:itwarranty/pam.git
cd pam
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
2. Lima VM `pam-prod` (`./tests/start-lima.sh`)
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
| `inventory/local-lima.yml` | Host `pam-lima` через Lima SSH |

### 5. Проверка SSH к шлюз-контейнеру

```bash
ssh -p 2222 -i lab/keys/gateway-lab.lab gateway-lab@127.0.0.1
ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1
ssh -p 2222 -i lab/keys/engineer-shell.lab engineer-shell@127.0.0.1
```

TOTP: otpauth URI в комментариях `group_vars/dev/lab.yml`.

**Jump:** прямой shell отклонён (`restrict,port-forwarding`).  
**Gateway:** интерактив на mock target; лог `gateway_*` на хосте.  
**Shell:** PTY + лог в `/var/log/pam_sessions/`.

### 6. Сценарии для отчёта

[CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md)

---

## Часть C. Работа с кодом

| Действие | Команда |
| :--- | :--- |
| Обновить repo | `git pull` |
| Новая фича | `git checkout -b feature/...` → PR в `main` |
| Синтаксис playbook | `ansible-playbook --syntax-check -i inventory/local-lima.yml site.yml` |
| Lab doctor (роль, TOTP, команда) | `./scripts/pam-doctor.sh engineer-jump` |
| Lab-образ с nullok (только dev) | `PAM_LAB_MODE=1 MFA_STRICT=0 ./trusted_download.sh` |
| Пересборка после Tier 2/3/4 scripts | `./trusted_download.sh` (wrapper, gateway, pty-inspector) → redeploy |

## Tier 4 (v1.0 GA)

| CLI | Назначение |
| :--- | :--- |
| `pam-session-search` | Поиск сессий в JSONL |
| `pam-session-watch` | Live moderation gateway log |
| `pam-ha-promote.sh` | Failover standby → primary |

OpenSpec: `openspec/changes/archive/2026-06-pam-free-tier4-ssh-pam-complete/`

Prod profile: `group_vars/prod.yml.example`

Prod-деплой (`inventory/hosts.yml` + Vault + Rocky 9) — только по согласованию с lead / CSO.

## Tier 5 — FIDO-Anchor MFA (v1.1)

| Действие | Команда / документ |
| :--- | :--- |
| Onboarding | [FIDO-Onboarding.md](./FIDO-Onboarding.md) |
| Lab FIDO operator | `PAM_FIDO_LAB=1 ./scripts/dev-up.sh` |
| Preflight check | `python3 scripts/preflight-fido-key.py < test/fixtures/fido-pubkey.txt` |
| JIT cert (sk) | `scripts/sign-operator-cert-jit.sh.example` |
| Prod vars | `pam_require_fido_pubkey: true`, `pam_mfa_mode: fido_totp` |

Dev lab по умолчанию: `pam_require_fido_pubkey: false` — `.lab` keys без изменений.

---

## Troubleshooting

- Инциденты и four-eyes: [Troubleshooting-Workflow.md](./Troubleshooting-Workflow.md)
- Command denylist: см. Workflow §5.4; проверьте `pam_shell_command_policy_enabled` и mount `/etc/ssh-pam/command_denylist`
- Break-glass: см. Workflow §5.5; preflight требует `incident_id`, `valid_until`, окно ≤ `pam_break_glass_max_hours`
- Lima VM: `tests/README.md`, `limactl shell pam-prod`
- Preflight fail: проверьте Rocky 9, Enforcing, whitelist, `pam_operators`

---

* Engineer Onboarding v1.6*
