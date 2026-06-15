# Сценарий демонстрации MT: Bastion для CSO (10 минут)

**Аудитория:** CSO, архитектор ИБ, аудитор  
**Цель:** показать Policy Gate, изоляцию и аудит — не «скрипт», а корпоративный control  
**Платформа:** Rocky Linux 9.x (x86_64), SELinux Enforcing, Rootless Podman  

**Связанные документы:** [Whitepaper](./MT-Bastion-Whitepaper.md) · [Workflow](./MT-Bastion-Troubleshooting-Workflow.md) · [Onboarding](./Engineer-Onboarding.md)

---

## Подготовка (до встречи, ~15 мин)

### Быстрый путь (рекомендуется)

```bash
cd mt-bastion
./scripts/dev-up.sh
```

Скрипт: lab-ключи (`lab/keys/`), сборка образа (`./trusted_download.sh`), Lima VM Rocky 9, Ansible deploy.  
Операторы — `group_vars/dev/lab.yml` + `group_vars/dev/operators_merge.yml` (без Vault).

### Ручной путь

```bash
cd mt-bastion
./trusted_download.sh                                    # MFA_STRICT=1, OCI-label
./tests/start-lima.sh                                    # instance: mt-bastion-prod
./tests/sync-artifacts.sh                                # tar → Lima VM (при необходимости)
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/local-lima.yml site.yml
```

**Lab-операторы:**

| Учётная запись | Роль | Ключ |
| :--- | :--- | :--- |
| `engineer-jump` | `access: jump` | `lab/keys/engineer-jump.lab` |
| `engineer-shell` | `access: shell` | `lab/keys/engineer-shell.lab` |

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
limactl shell mt-bastion-prod -- getenforce
limactl shell mt-bastion-prod -- cat /etc/redhat-release
```

### 1.2 Fail на нарушении политики (опционально)

Остановите VM, измените `bastion_permitted_targets: []` в `group_vars/all.yml` и запустите playbook — preflight должен прервать деплой с сообщением о пустом whitelist.

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
limactl shell mt-bastion-prod -- sudo -u mt_bastion podman image inspect mt_bastion_secure:latest --format '{{ index .Config.Labels "mt.global.mfa.strict" }}'
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

**Ожидание:** сессия через `ForceCommand` → `bastion-shell-wrapper.sh` → `script`.

### 4.2 Проверка лога на хосте

```bash
limactl shell mt-bastion-prod -- sudo ls -la /var/log/bastion_sessions/
limactl shell mt-bastion-prod -- sudo lsattr /var/log/bastion_sessions/*.log
```

**Ожидание:** файл `session_engineer-shell_*.log`, атрибут `a` (append-only). Каталог — `0750`, владелец `mt_bastion`.

### 4.3 auditd

```bash
limactl shell mt-bastion-prod -- sudo ausearch -k mt_bastion_session_logs | tail -5
```

**Ожидание:** события записи в каталог логов.

---

## Блок 5 — Инцидент (1 мин)

**Что сказать CSO:** «Kill-switch без потери доказательств.»

```bash
limactl shell mt-bastion-prod -- sudo -u mt_bastion podman stop mt_ssh_bastion
```

**Ожидание:** SSH-сессии обрываются; файлы в `/var/log/bastion_sessions/` остаются.

---

## Блок 6 — Supply chain (1 мин)

**Что сказать CSO:** «Immutable Air Gap — никаких runtime-загрузок.»

```bash
sha256sum -c /tmp/trusted_upstream_packages/SHA256SUMS
limactl shell mt-bastion-prod -- sudo -u mt_bastion podman exec mt_ssh_bastion ps aux
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
- [ ] `./trusted_download.sh` — label `mt.global.mfa.strict=1`
- [ ] Preflight pass, deploy complete
- [ ] Jump: direct shell fail, ProxyJump pass/fail по whitelist
- [ ] Shell: log file + `chattr +a`
- [ ] MFA без TOTP — fail
- [ ] Declarative revoke (опционально): `test-repo-key.sh revoke … --apply`
- [ ] [Whitepaper](./MT-Bastion-Whitepaper.md) · [Workflow](./MT-Bastion-Troubleshooting-Workflow.md)

---

## Блок 7 — Declarative revoke (опционально, 1 мин)

**Что сказать CSO:** «Отзыв доступа — декларативный sync, не ручная чистка.»

```bash
./scripts/test-repo-key.sh revoke tester-01 --apply
# или: удалить из bastion_operators → ansible-playbook -i inventory/local-lima.yml site.yml
```

**Ожидание:** каталог оператора удалён с хоста; `podman restart mt_ssh_bastion`; SSH под отозванным ключом — отказ.

---

*MT Global — MT: Bastion CSO Demo v1.2*
