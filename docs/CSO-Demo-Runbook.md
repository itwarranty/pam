# Сценарий демонстрации SSH PAM для CSO (~10 мин)

**Аудитория:** CSO, архитектор ИБ, аудитор  
**Цель:** показать Policy Gate, изоляцию и аудит — не «скрипт», а корпоративный control  
**Платформа:** Rocky Linux 9.x (x86_64), SELinux Enforcing, Rootless Podman  

**Связанные документы:** [Whitepaper](./Whitepaper.md) · [Workflow](./Troubleshooting-Workflow.md) · [Onboarding](./Engineer-Onboarding.md)

---

## Подготовка (до встречи, ~15 мин)

### Быстрый путь (рекомендуется)

```bash
cd pam
./scripts/dev-up.sh
```

Скрипт: lab-ключи (`lab/keys/`), сборка образа (`./trusted_download.sh`), Lima VM Rocky 9, Ansible deploy.  
Операторы — `group_vars/dev/lab.yml` + `group_vars/dev/operators_merge.yml` (без Vault).

### Ручной путь

```bash
cd pam
./trusted_download.sh                                    # MFA_STRICT=1, OCI-label
./tests/start-lima.sh                                    # instance: pam-prod
./tests/sync-artifacts.sh                                # tar → Lima VM (при необходимости)
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/local-lima.yml site.yml
```

**Lab-операторы:**

| Учётная запись | Роль | Ключ |
| :--- | :--- | :--- |
| `gateway-lab` | `access: gateway` | `lab/keys/gateway-lab.lab` |
| `engineer-jump` | `access: jump` | `lab/keys/engineer-jump.lab` |
| `engineer-shell` | `access: shell` | `lab/keys/engineer-shell.lab` |
| `engineer-audit` | `access: audit` | `lab/keys/engineer-audit.lab` |
| `breakglass-lab` | `access: shell` (break-glass) | `lab/keys/breakglass-lab.lab` |

TOTP-секреты — в комментариях `group_vars/dev/lab.yml` (фиксированные для lab).

---

## Блок 1 — Policy Gate (2 мин)

**Что сказать CSO:** «Деплой не начинается, пока хост не соответствует эталону. Fail-Fast, без silent fallback.»

### 1.1 Preflight на Rocky 9

```bash
ansible-playbook -i inventory/local-lima.yml site.yml
```

**Ожидание:** `[CSO] Preflight` pass → deploy complete.

**Показать CSO:** Rocky 9, x86_64, `getenforce` = Enforcing, whitelist не пуст, операторы заданы.

```bash
limactl shell pam-prod -- getenforce
limactl shell pam-prod -- cat /etc/redhat-release
```

### 1.2 Fail на нарушении политики (опционально)

Остановите VM, измените `pam_permitted_targets: []` в `group_vars/all.yml` и запустите playbook — preflight должен прервать деплой с сообщением о пустом whitelist.

---

## Блок 2 — Jump без shell (2 мин)

**Что сказать CSO:** «Jump-оператор не получает PTY — только audited forwarding.»

### 2.1 Прямой login jump-оператора — отказ

```bash
ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1
```

**Ожидание:** `PTY allocation request failed` / `shell request failed`.  
**Механизм:** `restrict,port-forwarding,permitopen="..."` в `templates/authorized_keys.j2`.

### 2.2 ProxyJump на whitelist — успех

```bash
ssh -J engineer-jump@127.0.0.1:2222 -i lab/keys/engineer-jump.lab -p 22 user@10.0.1.10
```

**Ожидание:** подключение к цели (если mock/target доступен в lab).

### 2.3 ProxyJump на не-whitelisted host — отказ

```bash
ssh -J engineer-jump@127.0.0.1:2222 -i lab/keys/engineer-jump.lab user@10.0.99.99
```

**Ожидание:** `open failed: administratively prohibited` / `connect failed`.

---

## Блок 3 — MFA strict (1 мин)

**Что сказать CSO:** «Prod-образ только с MFA_STRICT=1; после `podman load` verify проверяет OCI-label.»

### 3.1 Вход без TOTP

```bash
ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1
# не вводить код TOTP
```

**Ожидание:** отказ аутентификации.

### 3.2 Verify образа

```bash
limactl shell pam-prod -- sudo -u pam podman image inspect pam_secure:latest --format '{{ index .Config.Labels "pam.mfa.strict" }}'
```

**Ожидание:** `1`

---

## Блок 4 — Shell-сессия и аудит (2 мин)

**Что сказать CSO:** «Интерактивный доступ — только `access: shell`, с записью TTY и append-only логом.»

### 4.1 Вход shell-оператора

```bash
ssh -p 2222 -i lab/keys/engineer-shell.lab engineer-shell@127.0.0.1
# pubkey + TOTP из group_vars/dev/lab.yml
```

**Ожидание:** сессия через `ForceCommand` → `pam-shell-wrapper.sh` → `script`.

### 4.2 Проверка лога на хосте

```bash
limactl shell pam-prod -- sudo ls -la /var/log/pam_sessions/
limactl shell pam-prod -- sudo lsattr /var/log/pam_sessions/*.log
```

**Ожидание:** файл `session_engineer-shell_*.log`, атрибут `a` (append-only). Каталог — `0750`, владелец `gateway`.

### 4.2a Tamper-evident sidecar (Tier 1)

После `exit` из shell-сессии:

```bash
limactl shell pam-prod -- sudo ls -la /var/log/pam_sessions/*.sha256 /var/log/pam_sessions/*.meta
limactl shell pam-prod -- sudo sha256sum -c /var/log/pam_sessions/session_engineer-shell_*.log.sha256
limactl shell pam-prod -- sudo cat /var/log/pam_sessions/session_engineer-shell_*.log.meta
```

**Ожидание:** `sha256sum -c` → OK; `.meta` содержит `SHA256=`, `UTC=`, `USER=`, `CLIENT=`.

> После изменения `pam-shell-wrapper.sh` пересоберите образ: `./trusted_download.sh` и redeploy.

### 4.3 auditd

```bash
limactl shell pam-prod -- sudo ausearch -k pam_session_logs | tail -5
```

**Ожидание:** события записи в каталог логов.

---

## Блок 5 — Инцидент (1 мин)

**Что сказать CSO:** «Kill-switch без потери доказательств.»

```bash
limactl shell pam-prod -- sudo -u pam podman stop ssh_pam
```

**Ожидание:** SSH-сессии обрываются; файлы в `/var/log/pam_sessions/` остаются.

---

## Блок 6 — Supply chain (1 мин)

**Что сказать CSO:** «Immutable Air Gap — никаких runtime-загрузок.»

```bash
sha256sum -c /tmp/trusted_upstream_packages/SHA256SUMS
limactl shell pam-prod -- sudo -u pam podman exec ssh_pam ps aux
```

**Ожидание:** checksum OK; в контейнере `sshd.pam`, без `apk`/`dnf` в runtime.

---

## Шпаргалка «Избегать / Говорить»

| Не говорить | Говорить |
| :--- | :--- |
| «100% гарантия от ошибок инженера» | «Policy Gate + whitelist + restrict keys + audit trail» |
| «Сертифицировано PCI/КИИ» | «Контроли спроектированы под требования PCI-DSS 4.0 и КИИ» |
| «Логи невозможно удалить» | «At-birth `chattr +a` на каждый log-файл + auditd; рекомендуем SIEM» |

---

## Чек-лист перед пресейлом

- [ ] `./scripts/dev-up.sh` или эквивалентный ручной деплой
- [ ] Lima Rocky 9: `getenforce` = Enforcing
- [ ] `./trusted_download.sh` — label `pam.mfa.strict=1`
- [ ] Preflight pass, deploy complete
- [ ] Jump: direct shell fail, ProxyJump pass/fail по whitelist
- [ ] Shell: log file + `chattr +a` + `.sha256` / `.meta` sidecars (после rebuild образа)
- [ ] Compliance verify: `--tags verify_compliance` или `pam-compliance-verify.sh`
- [ ] MFA без TOTP — fail
- [ ] Declarative revoke (опционально): `test-repo-key.sh revoke … --apply`
- [ ] [Whitepaper](./Whitepaper.md) · [Workflow](./Troubleshooting-Workflow.md)

---

## Блок 7 — Declarative revoke (опционально, 1 мин)

**Что сказать CSO:** «Отзыв доступа — декларативный sync, не ручная чистка.»

```bash
./scripts/test-repo-key.sh revoke tester-01 --apply
# или: удалить из pam_operators → ansible-playbook -i inventory/local-lima.yml site.yml
```

**Ожидание:** каталог оператора удалён с хоста; `podman restart ssh_pam`; SSH под отозванным ключом — отказ.

---

## Блок 8 — Compliance verify (Tier 1, 1 мин)

**Что сказать CSO:** «Периодический аудит состояния шлюза — одной командой, exit code для мониторинга.»

```bash
ansible-playbook -i inventory/local-lima.yml site.yml --tags verify_compliance
# или на хосте:
limactl shell pam-prod -- sudo bash -c 'cd /path/to/gateway && ./scripts/pam-compliance-verify.sh'
```

**Ожидание:** все checks PASS, exit 0. При deliberate drift (например `podman stop ssh_pam`) — FAIL.

---

## Блок 9 — Source IP restriction (Tier 1, опционально, 1 мин)

**Что сказать CSO:** «Per-operator `from=` в authorized_keys; опционально firewalld CIDR.»

```bash
# Пример prod: allowed_sources в pam_operators
grep from= /home/gateway/operators/*/.ssh/authorized_keys
```

**Демо отказа:** задайте `allowed_sources: ["203.0.113.0/24"]` (без 127.0.0.0/8) → SSH с localhost получит `Permission denied (publickey)` до MFA.

Strict mode: `pam_require_source_ip: true` — preflight fail без `allowed_sources` у каждого оператора.

---

## Блок 10 — JIT expiry (Tier 1 Phase B, 1 мин)

**Что сказать CSO:** «Окно доступа в YAML — после `valid_until` оператор удаляется автоматически, без ручной чистки.»

```bash
# Lab: jit-expired-test в group_vars/dev/jit_lab.yml (valid_until 2020)
ansible-playbook -i inventory/local-lima.yml site.yml
limactl shell pam-prod -- sudo test ! -d /home/gateway/operators/jit-expired-test && echo OK

# Периодический purge на prod
ansible-playbook site.yml --tags jit_purge
```

**Ожидание:** каталог `jit-expired-test` отсутствует; в логе Ansible — `JIT purge: jit-expired-test (expired)`.

---

## Блок 11 — SSH User CA (Phase C, опционально, 1 мин)

**Что сказать CSO:** «Prod — короткоживущие user certificates; private CA никогда не на шлюзе.»

```bash
# Offline signing (admin workstation):
export PAM_USER_CA_KEY=/secure/user-ca
./scripts/sign-operator-cert.sh.example engineer-jump ~/.ssh/engineer-jump.key 72

# QA deploy (after copying qa.yml.example → group_vars/qa.yml):
ansible-playbook -i inventory/qa.yml site.yml
```

**Ожидание:** `TrustedUserCAKeys` в контейнере; вход по cert + TOTP. Live QA — после выдачи org CA pubkey.

---

## Блок 12 — Incident log naming (Tier 2 Phase A, 1 мин)

**Что сказать CSO:** «Лог сессии привязан к тикету INC — имя файла содержит номер инцидента для SIEM и WORM.»

```bash
ssh -p 2222 engineer-shell@127.0.0.1
# exit после входа
ls -la /var/log/pam_sessions/session_INC-LAB-SHELL-01_*
```

**Ожидание:** basename `session_INC-LAB-SHELL-01_engineer-shell_*.log` + `.sha256` + `.meta` с `INCIDENT=INC-LAB-SHELL-01`.

> После изменения wrapper/policy/audit scripts: `./trusted_download.sh` и redeploy.

---

## Блок 13 — Command denylist (Tier 2 Phase B, 1 мин)

**Что сказать CSO:** «Опасные команды в shell-сессии блокируются политикой CSO, отказ пишется в syslog.»

```bash
ssh -p 2222 engineer-shell@127.0.0.1
rm -rf /
# ожидается отказ, сессия продолжается
exit
journalctl -t pam-deny --since "5 min ago" | tail -5
```

**Ожидание:** сообщение об отказе в PTY; запись в journal с тегом `pam-deny`.

---

## Блок 14 — Audit readonly (Tier 2 Phase C, 1 мин)

**Что сказать CSO:** «Аудитор читает session logs без jump и без записи на диск.»

```bash
ssh -p 2222 engineer-audit@127.0.0.1
ls /var/log/pam_sessions/
less /var/log/pam_sessions/session_INC-LAB-SHELL-01_engineer-shell_*.log
cat /etc/passwd
# ожидается отказ
exit
```

**Ожидание:** `ls`/`less` на session logs — OK; `cat /etc/passwd` — denied.

---

## Блок 15 — SSH rate limit (Tier 2 Phase D, опционально, 1 мин)

**Что сказать CSO:** «Brute-force на SSH-порт ограничивается firewalld (по умолчанию выкл. в lab).»

```bash
# В group_vars: pam_ssh_rate_limit_enabled: true
firewall-cmd --list-rich-rules | grep limit
./scripts/pam-compliance-verify.sh
```

**Ожидание:** rich rule с `limit value`; compliance verify — `rate_limit` PASS при включённой опции.

---

## Блок 16 — Break-glass (Tier 2 Phase E, 1 мин)

**Что сказать CSO:** «Аварийный доступ — только с тикетом, коротким окном JIT и усиленным аудитом.»

```bash
ssh -p 2222 breakglass-lab@127.0.0.1
exit
ausearch -k pam_break_glass_session 2>/dev/null | tail -3
journalctl -t pam-break-glass --since "5 min ago" | tail -3
```

**Ожидание:** syslog/journal с маркером break-glass; auditd key `pam_break_glass_session` при `pam_break_glass_audit_enabled: true`.

---

## Блок 17 — SSH Gateway (Tier 3, 2 мин)

**Что сказать CSO:** «Инженер работает на target через шлюз; полный TTY-лог на нашей стороне; ключ target оператор не видит.»

```bash
ssh -p 2222 -i lab/keys/gateway-lab.lab gateway-lab@127.0.0.1
# interactive on mock target (gateway-target), then exit
limactl shell pam-prod -- sudo ls /var/log/pam_sessions/gateway_INC-LAB-GW-01_*
limactl shell pam-prod -- sudo sha256sum -c /var/log/pam_sessions/gateway_*.log.sha256
```

**Ожидание:** log + sidecars; `.meta` содержит `MODE=gateway`, `TARGET=lab-mock-01`.

> После изменения gateway wrappers: `./trusted_download.sh` (в Lima) и redeploy.

---

## Блок 18 — Session kill (Tier 3, 1 мин)

**Что сказать CSO:** «Активную gateway-сессию можно разорвать без остановки всего шлюза.»

```bash
# Terminal 1: gateway-lab session (keep open)
# Terminal 2:
limactl shell pam-prod -- sudo pam-session-ctl list
limactl shell pam-prod -- sudo pam-session-ctl kill <session-id>
journalctl -t pam-session-kill --since "2 min ago" | tail -3
```

**Ожидание:** сессия завершена ≤10s; syslog `pam-session-kill`.

---

## Блок 19 — Jump vs Gateway (Tier 3 narrative, 1 мин)

**Что сказать CSO:** «Jump — для automation и connect-audit; gateway — для интерактива на prod с полным доказательством.»

См. [SSH-PAM-Overview.md](./SSH-PAM-Overview.md) — five auditor questions.

---

## Блок 20 — Session search (Tier 4, 1 мин)

**Что сказать CSO:** «Историю gateway-сессий ищем по оператору и дате без SIEM.»

```bash
limactl shell pam-prod -- sudo pam-session-search --operator gateway-lab --since 7d
limactl shell pam-prod -- sudo pam-session-search --json | jq -r '.[].session_id' | head
```

**Ожидание:** строки из `sessions.jsonl` за окно; `--json` — machine-readable.

---

## Блок 21 — Command policy v2 (Tier 4, 1 мин)

**Что сказать CSO:** «Опасная команда блокируется на шлюз до попадания на target — без remote rc на сервере. v2 обязателен в prod; compliance проверяет PTY inspector в runtime.»

```bash
./scripts/pam-compliance-verify.sh | grep command_policy_v2
# gateway-lab session on mock target:
rm -rf /
# ожидается отказ в PTY
journalctl -t pam-deny --since "5 min ago" | tail -5
```

**Ожидание:** deny message; v2 enabled in `gateway_lab.yml`.

---

## Блок 22 — Live session watch (Tier 4, 1 мин)

**Что сказать CSO:** «Модератор видит ввод в реальном времени — audit trail фиксирует начало наблюдения.»

```bash
# Terminal 1: gateway session (keep open)
# Terminal 2:
limactl shell pam-prod -- sudo pam-session-ctl list
limactl shell pam-prod -- sudo pam-session-watch <session-id>
grep moderator_watch_start /var/log/pam_sessions/sessions.jsonl | tail -1
```

**Ожидание:** live tail gateway log; JSONL event с session_id и moderator user.

---

## Блок 23 — FIDO-Anchor MFA (Tier 5, опционально, 1 мин)

**Что сказать CSO:** «Phishing-resistant первый фактор — Touch ID / YubiKey на ноутбуке; TOTP остаётся на шлюз. Без proprietary client.»

```bash
# Требуется FIDO hardware + PAM_FIDO_LAB=1 deploy:
PAM_FIDO_LAB=1 ./scripts/dev-up.sh
ssh -p 2222 -i lab/keys/engineer-fido.lab engineer-fido@127.0.0.1
python3 scripts/preflight-fido-key.py < test/fixtures/fido-pubkey.txt
```

**Ожидание:** touch/PIN при SSH; TOTP prompt; preflight script exit 0 на sk fixture.

> Без hardware — пропустить блок; lab regression на `engineer-jump.lab` без FIDO.

---

* CSO Demo v1.9 (v1.1.0)*
