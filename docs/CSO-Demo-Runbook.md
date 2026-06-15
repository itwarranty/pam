# Сценарий демонстрации MT: Bastion для CSO (10 минут)

**Аудитория:** CSO, архитектор ИБ, аудитор  
**Цель:** показать Policy Gate, изоляцию и аудит — не «скрипт», а корпоративный control  
**Подготовка:** Rocky Linux 9 VM (`./tests/start-lima.sh`), образ собран (`./trusted_download.sh`), операторы в `group_vars/all.yml`

---

## Подготовка (до встречи, 15 мин)

```bash
cd mt-bastion

# 1. Сборка prod-образа
./trusted_download.sh

# 2. Lima VM (Rocky 9 x86_64, SELinux Enforcing)
./tests/start-lima.sh

# 3. Копирование tar на guest (если не через mount + symlink)
limactl shell mt-bastion-prod -- sudo cp /path/to/mt_bastion_image.tar /tmp/trusted_upstream_packages/

# 4. Деплой
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/local-lima.yml site.yml
```

Заполните `bastion_operators` минимум двумя пользователями:

- `engineer-jump` — `access: jump`
- `engineer-shell` — `access: shell`

---

## Блок 1 — Policy Gate (2 мин)

**Что сказать CSO:** «Деплой не начинается, пока хост не соответствует эталону. Fail-Fast, без silent fallback.»

### 1.1 Fail на неподдерживаемой ОС (опционально, если есть Ubuntu VM)

```bash
ansible-playbook -i inventory/wrong-os.yml site.yml
```

**Ожидание:** fail на `[CSO] Rocky Linux 9.x` с явным сообщением.

### 1.2 Pass на Rocky 9

```bash
ansible-playbook -i inventory/local-lima.yml site.yml
```

**Ожидание:** preflight green → deploy complete.

**Показать CSO:** вывод `tasks/preflight_cso.yml` — Rocky 9, x86_64, Enforcing.

---

## Блок 2 — Jump без shell (2 мин)

**Что сказать CSO:** «Jump-оператор не может получить интерактивную сессию — только audited forwarding.»

### 2.1 Прямой login jump-оператора — отказ

```bash
ssh -p 2222 -i ~/.ssh/id_ed25519 engineer-jump@127.0.0.1
```

**Ожидание:** `PTY allocation request failed` или `shell request failed` / disconnect.  
**Механизм:** `restrict,port-forwarding` в `authorized_keys`.

### 2.2 ProxyJump на whitelist — успех

```bash
ssh -J engineer-jump@127.0.0.1:2222 -p 22 user@10.0.1.10
```

**Ожидание:** подключение к цели (если mock/target доступен в lab).

### 2.3 ProxyJump на не-whitelisted host — отказ

```bash
ssh -J engineer-jump@127.0.0.1:2222 user@10.0.99.99
```

**Ожидание:** `open failed: administratively prohibited` / `connect failed`.

---

## Блок 3 — MFA strict (1 мин)

**Что сказать CSO:** «В prod образ собран с MFA_STRICT=1; preflight проверяет OCI-label.»

### 3.1 Вход без TOTP

```bash
ssh -p 2222 engineer-jump@127.0.0.1 -i key
# не вводить код TOTP
```

**Ожидание:** отказ аутентификации.

### 3.2 Показать verify образа

```bash
limactl shell mt-bastion-prod -- sudo -u mt_bastion podman image inspect mt_bastion_secure:latest --format '{{ index .Config.Labels "mt.global.mfa.strict" }}'
```

**Ожидание:** `1`

---

## Блок 4 — Shell-сессия и аудит (2 мин)

**Что сказать CSO:** «Интерактивный доступ — только роль shell, с записью TTY и append-only логом.»

### 4.1 Вход shell-оператора

```bash
ssh -p 2222 engineer-shell@127.0.0.1
# pubkey + TOTP
```

**Ожидание:** интерактивная сессия через `ForceCommand` + `script`.

### 4.2 Проверка лога на хосте

```bash
limactl shell mt-bastion-prod -- sudo ls -la /var/log/bastion_sessions/
limactl shell mt-bastion-prod -- sudo lsattr /var/log/bastion_sessions/*.log
```

**Ожидание:** файл `session_engineer-shell_*.log`, атрибут `a` (append-only).

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

**Ожидание:** активные SSH-сессии обрываются; файлы в `/var/log/bastion_sessions/` остаются.

---

## Блок 6 — Supply chain (1 мин)

**Что сказать CSO:** «Immutable Air Gap — никаких runtime-загрузок.»

```bash
sha256sum -c /tmp/trusted_upstream_packages/SHA256SUMS
limactl shell mt-bastion-prod -- sudo -u mt_bastion podman exec mt_ssh_bastion ps aux
```

**Ожидание:** checksum OK; в контейнере только `sshd`, без `apk`/`dnf` в runtime.

---

## Шпаргалка «Избегать / Говорить»

| Не говорить | Говорить |
|:---|:---|
| «100% гарантия от ошибок инженера» | «Policy Gate + whitelist + restrict keys + audit trail» |
| «Сертифицировано PCI/КИИ» | «Контроли спроектированы под требования PCI-DSS 4.0 и КИИ» |
| «Логи невозможно удалить» | «At-birth append-only + auditd; рекомендуем SIEM» |

---

## Чек-лист перед пресейлом

- [ ] `./tests/start-lima.sh` — VM Rocky 9, `getenforce` = Enforcing
- [ ] `./trusted_download.sh` — образ с label `mt.global.mfa.strict=1`
- [ ] `ansible-playbook` — preflight pass
- [ ] Jump: direct shell fail, ProxyJump pass
- [ ] Shell: log file + `chattr +a`
- [ ] MFA без TOTP — fail
- [ ] Whitepaper: `docs/MT-Bastion-Whitepaper.md`
- [ ] Workflow: `docs/MT-Bastion-Troubleshooting-Workflow.md`

---

*MT Global — MT: Bastion CSO Demo v1.0*
