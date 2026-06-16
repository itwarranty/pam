# РЕГЛАМЕНТ И ВОРКФЛОУ ПРОВЕДЕНИЯ ТРАБЛШУТИНГА «MT: BASTION»

**Статус:** Enforced (обязателен к исполнению операторами MT Global и ИБ-службами Заказчика)  
**Концепция:** Dual Custody / принцип «четырёх глаз» (Four-Eyes Principle)  
**Версия:** 1.2  
**Связанные документы:** [MT-Bastion-Whitepaper.md](./MT-Bastion-Whitepaper.md), [CSO-Demo-Runbook.md](./CSO-Demo-Runbook.md), [Engineer-Onboarding.md](./Engineer-Onboarding.md)

---

## Область применения

Настоящий регламент описывает сквозной жизненный цикл инцидента удалённой поддержки в закрытых контурах (Air Gap / КИИ): от регистрации заявки до закрытия сессии и формирования неотчуждаемого аудиторского следа.

**Платформа:** Rocky Linux 9.x (x86_64), SELinux Enforcing, Rootless Podman — иные конфигурации блокируются preflight-проверкой (`tasks/preflight_cso.yml`).

---

## ЭТАП 1: Инициация инцидента и Just-in-Time авторизация

### 1.1 Регистрация инцидента

При возникновении технического сбоя в закрытом контуре Заказчика дежурный инженер MT Global или администратор Заказчика регистрирует тикет в ITSM-системе (Service Desk) с присвоением уникального ID (например, `INC-2026-8942`).

**Обязательные поля тикета:**

- описание инцидента и затронутые системы;
- классификация по критичности;
- контакт ответственного со стороны Заказчика;
- ссылка на утверждённое окно доступа (п. 1.2).

### 1.2 Запрос временного окна доступа (Just-in-Time)

Операторы MT Global **по умолчанию не имеют** постоянного доступа к бастиону. Старший инженер MT Global формирует запрос на проведение работ, в котором указывает:

- перечень инженеров, привлекаемых к диагностике (строго именные учётные записи из массива `bastion_operators`);
- временное окно проведения работ (например, с 14:00 до 16:00 UTC+3);
- список целевых `host:port` оборудования внутри КИИ/Air Gap сети (формат `PermitOpen`, без CIDR);
- тип доступа каждого инженера:
  - `access: shell` — интерактивная сессия с записью TTY (сценарий «четырёх глаз»);
  - `access: jump` — только ProxyJump к whitelist-целям (без интерактивного shell).

### 1.3 Одобрение ИБ-директором (CSO) Заказчика

CSO или уполномоченный офицер безопасности Заказчика сверяет запрос с регламентом:

- проверяет, что запрашиваемые инженеры зафиксированы в политике деплоя (`bastion_operators`);
- подтверждает актуальность whitelist (`bastion_permitted_targets` / персональные `permit_open`);
- санкционирует применение обновлённой конфигурации Ansible и перевыпуск плейбука:

```bash
ansible-playbook site.yml
```

> **Технический контроль продукта:** изменения прав и whitelist вносятся **только** декларативно через Ansible. Ручное редактирование `authorized_keys` на хосте запрещено — будет перезаписано при следующем деплое.

---

## ЭТАП 2: Подключение и двухфакторный барьер

### 2.1 Проверка первого фактора (SSH-ключ)

Инженер MT Global инициирует SSH-сессию со своего рабочего места на кастомный порт бастиона (по умолчанию `2222`):

```bash
ssh -p 2222 engineer_support@bastion.client.internal
```

**Цепочка проверок:**

1. **firewalld** (Rocky Linux 9) пропускает трафик на порт `bastion_ssh_port`.
2. **Rootless Podman** принимает соединение в контейнере `mt_ssh_bastion` (контекст пользователя `mt_bastion` на хосте).
3. **sshd** (контейнер, `sshd.pam`) сверяет ключ или user certificate с данными оператора:
   - хост (read-only mount): `{{ bastion_home }}/operators/<operator>/`
   - entrypoint копирует в контейнер: `/home/<operator>/.ssh/authorized_keys`, `.google_authenticator`

**Дополнительно для роли `jump`:** в `authorized_keys` применяются опции `restrict,port-forwarding,permitopen="..."` — прямой интерактивный shell **заблокирован** на уровне OpenSSH.

### 2.2 Проверка второго фактора (Offline TOTP)

SSH запрашивает одноразовый шестизначный код:

```text
Verification code:
```

Инженер генерирует код в приложении Authenticator или на аппаратном токене на **изолированном устройстве** (без доступа в Интернет на стороне Заказчика).

**PAM** (`pam_google_authenticator.so`) сверяет код локально — без сетевых обращений (Air Gap). Prod-образ: `MFA_STRICT=1`, OCI-label проверяется в `tasks/verify_image_cso.yml` после `podman load`.

| Результат | Действие системы |
| :--- | :--- |
| Код верен | Переход к этапу 3 (shell) или установка forwarding-канала (jump) |
| Код неверен / таймаут | Сессия отклоняется; **auditd** на хосте фиксирует событие (`mt_bastion_ssh_connect`) |

---

## ЭТАП 3: Инициация контролируемой среды (модерация «в разрыве»)

> **Применимость:** данный этап обязателен для инцидентов с `access: shell`. Для чистого ProxyJump (`access: jump`) используется сценарий из п. 4.1 без shared tmux.

После успешной авторизации инженер MT Global попадает во внутренний shell бастиона через `ForceCommand` → `bastion-shell-wrapper.sh`. Назначенный **ИБ-модератор** Заказчика (`client_moderator`, роль `access: shell`) уже находится на бастионе под своей учётной записью.

### 3.1 Сборка консольного моста (двойной контроль)

ИБ-модератор Заказчика инициирует shared-сессию tmux, привязанную к тикету:

```bash
# Выполняет модератор Заказчика
sudo mkdir -p /var/run/shared_tmux && sudo chmod 1770 /var/run/shared_tmux
tmux -S /var/run/shared_tmux/bridge_INC-2026-8942 new-session -s INC-2026-8942
```

Инженер MT Global подключается в режиме **только чтение**:

```bash
# Выполняет инженер MT Global
tmux -S /var/run/shared_tmux/bridge_INC-2026-8942 attach-session -t INC-2026-8942 -r
```

> **Примечание:** каталог сокета и права доступа настраиваются модератором до начала сессии. Рекомендуется именовать сокет по ID тикета для трассируемости.

### 3.2 Фиксация атомарного аудиторского следа (At-Birth Protection)

При открытии TTY `bastion-shell-wrapper.sh` перехватывает сессию и запускает `script`:

```bash
exec script -q -f -c "/bin/bash --login" \
  "/var/log/bastion_sessions/session_engineer_support_20260615_143022.log"
```

**На хосте** (volume `/var/log/bastion_sessions`, владелец `mt_bastion`, mode `0750`):

- на каждый новый `.log` — атрибут `chattr +a` (append-only) в `bastion-shell-wrapper.sh` и при старте entrypoint;
- **auditd** регистрирует операции записи (`mt_bastion_session_logs`).

---

## ЭТАП 4: Проведение траблшутинга и эскалация контроля

### 4.1 Прозрачный просмотр и экспертиза (режим Read-Only)

Инженер MT Global видит консоль, но **не может вводить символы** (флаг `-r` в tmux). Диагностические команды диктуются модератору голосом или через согласованный текстовый канал вне бастиона.

Модератор Заказчика:

- вводит команды на целевых системах;
- при необходимости выполняет ProxyJump с бастиона на внутренние хосты из whitelist (`PermitOpen`);
- **не раскрывает** административные пароли инфраструктуры третьим лицам.

### 4.2 Временное делегирование ввода (интерактивный режим)

Если характер неисправности требует прямого ввода со стороны эксперта MT Global, ИБ-модератор **осознанно** снимает режим read-only:

```bash
# На стороне модератора: переподключение без -r или Ctrl+B → I (switch pane / grant input)
# Рекомендуется: явная фиксация в тикете «делегирование ввода с HH:MM»
```

Инженер MT Global вводит команды напрямую. Модератор **непрерывно** контролирует ввод на своём мониторе. Все действия продолжают записываться в append-only лог.

### 4.3 Перехват сессии модератором (защита от ошибки / инсайдера)

При попытке ввести несанкционированную или деструктивную команду:

```text
[Инженер MT пытается ввести опасную команду]
              │
              ▼  (отображается на экране модератора)
[ИБ-модератор: Ctrl+B → d  или  kill-session]
              │
              ▼
[Сессия инженера detached] → [команда не исполнена на целевой ОС]
```

Модератор документирует инцидент в тикете. При систематических нарушениях — эскалация CSO и отзыв доступа через обновление `bastion_operators`.

### 4.4 Kill-switch (экстренная остановка)

При компрометации или подозрительной активности администратор Заказчика:

```bash
sudo -u mt_bastion podman stop mt_ssh_bastion
```

Активные SSH-сессии разрываются. Логи в `/var/log/bastion_sessions/` **сохраняются** на хосте.

---

## ЭТАП 5: Деавторизация, сбор и архивация улик

### 5.1 Закрытие сессии

По завершении работ модератор Заказчика:

1. завершает tmux-сессию (`exit` / `tmux kill-session`);
2. фиксирует время окончания в тикете;
3. инженер MT Global деавторизуется.

### 5.2 Just-in-Time блокировка

По истечении утверждённого временного окна доступа **обязательно** одно из:

**A. Автоматический путь (рекомендуется):**

1. Задать `valid_until` в `bastion_operators` (ISO8601 с timezone).
2. Включить timer: `bastion_jit_timer_enabled: true` **или** периодически:
   ```bash
   ansible-playbook site.yml --tags jit_purge
   ```
3. Плейбук выполняет `jit_filter_operators.yml` → операторы с `valid_until` в прошлом исключаются из effective списка → `purge_revoked_operators.yml`.

**B. Ручной путь:**

1. Удалить учётные записи из `bastion_operators` (prod) или dev/test YAML (lab);
2. `ansible-playbook site.yml`;
3. Зафиксировать закрытие окна в ITSM.

**Технический контроль:** `tasks/purge_revoked_operators.yml` автоматически:

- удаляет каталоги операторов на хосте (`{{ operators_home }}/<name>/`);
- удаляет TOTP onboarding (`generated/mfa/<host>/<name>.mfa.txt`);
- удаляет Unix-учётки и `/home/<name>` внутри контейнера;
- перезапускает `mt_ssh_bastion` (handler в `site.yml`).

Entrypoint (`bastion-entrypoint.sh`) дополнительно удаляет учётки, отсутствующие в read-only mount `/etc/bastion/operators`, при каждом старте контейнера.

> **Примечание:** сузить доступ можно через `permit_open`, но `bastion_permitted_targets` не может быть пуст — preflight прервёт деплой.

### 5.3 Формирование отчёта для CSO и SIEM

1. Лог-файл сессии закрывается. **auditd** фиксирует операции записи и доступа к каталогу.
2. **Tamper-evident sidecar** (Tier 1): при выходе из shell `bastion-shell-wrapper.sh` создаёт:
   - `<session>.log.sha256` — GNU-формат для `sha256sum -c`;
   - `<session>.log.meta` — `SHA256=`, `UTC=`, `USER=`, `INCIDENT=`, `CLIENT=`.
3. Контрольная сумма включается в тикет `INC-2026-8942`:

   ```bash
   sha256sum -c /var/log/bastion_sessions/session_engineer-shell_20260615_143022.log.sha256
   cat /var/log/bastion_sessions/session_engineer-shell_20260615_143022.log.meta
   ```

4. Текстовый лог прикладывается к тикету как доказательство выполненных работ.
5. Офицер безопасности Заказчика может воспроизвести сессию посимвольно:

   ```bash
   less /var/log/bastion_sessions/session_engineer_support_20260615_143022.log
   ```

6. События **auditd** (ключи `mt_bastion_session_logs`, `mt_bastion_ssh_connect`, `mt_bastion_break_glass_session`) направляются в SIEM через rsyslog LOCAL6 при `bastion_siem_forward_enabled: true` (см. Whitepaper §6).

### 5.4 Shell command policy (Tier 2)

При `bastion_shell_command_policy_enabled: true` опасные интерактивные команды в shell-сессии блокируются denylist (`/etc/bastion/command_denylist`).

1. Отказ фиксируется в syslog/journal с тегом `mt-bastion-deny`.
2. Сессия **не** прерывается — оператор получает сообщение об отказе.
3. Denylist редактируется только через Ansible (`bastion_shell_command_denylist`), не вручную в контейнере.
4. Jump-операторы (`access: jump`) не затрагиваются.

**Диагностика:**

```bash
journalctl -t mt-bastion-deny --since "1 hour ago"
podman exec mt_ssh_bastion cat /etc/bastion/command_denylist
```

### 5.5 Break-glass emergency access (Tier 2)

Аварийный профиль включается только при `bastion_break_glass_enabled: true` и обязательных полях оператора:

- `break_glass: true`
- непустой `incident_id`
- `valid_until` (и опционально `valid_from`) — окно ≤ `bastion_break_glass_max_hours` (по умолчанию 4 ч)

При входе:

1. Shell wrapper выставляет `MT_BASTION_BREAK_GLASS=1` и пишет syslog `mt-bastion-break-glass`.
2. auditd (при `bastion_break_glass_audit_enabled`) логирует ключ `mt_bastion_break_glass_session`.
3. Маркер `.mt-bastion-break-glass` в каталоге оператора на хосте.

**Закрытие окна:** по истечении `valid_until` — `jit_purge` удаляет оператора (как Tier 1 JIT).

### 5.6 Gateway session kill (Tier 3)

Активные gateway-сессии регистрируются в `{{ bastion_runtime_dir }}/sessions/` (mount в контейнер `/run/mt-bastion/sessions/`).

```bash
bastion-session-ctl list
bastion-session-ctl kill <session-id>
bastion-session-ctl kill --operator engineer1
ansible-playbook site.yml --tags session_kill -e bastion_session_kill_id=<id>
```

**JIT purge** (`--tags jit_purge`) завершает сессии отозванных операторов до purge каталогов.

**JSONL для SIEM:**

```bash
grep gateway_start /var/log/bastion_sessions/sessions.jsonl | tail -5
jq -r 'select(.event=="gateway_end")' /var/log/bastion_sessions/sessions.jsonl
```

### 5.7 Session search и live moderation (Tier 4)

**Поиск завершённых сессий** (JSONL + optional grep по `.log`):

```bash
bastion-session-search --operator engineer1 --since 7d
bastion-session-search --target prod-app-01 --json
bastion-session-search --grep "rm -rf" --since 24h
```

Требует `jq` на хосте (Ansible `install_tier4_tools.yml` при `bastion_session_search_enabled`).

**Live moderation** (четырёх глаз на активной gateway-сессии):

```bash
bastion-session-ctl list
bastion-session-watch <session-id>
# JSONL: moderator_watch_start в sessions.jsonl
```

Модератор: пользователь с `access: audit` или член группы `mt_bastion_moderators` (sudo на host CLI).

**Command policy v2** (gateway): destructive команды блокируются на бастion PTY до SSH к target; v1 remote rc — fallback при `bastion_gateway_command_policy_v2_enabled: false`.

---

## Блок-схема воркфлоу (слайд для презентации)

```text
[1. Service Desk: тикет INC-XXXX]
              │
              v
[2. Одобрение CSO + Ansible: bastion_operators / PermitOpen]
              │
              v
[3. Вход: SSH-ключ + Offline TOTP]
              │
              v
[4. Tmux «4 глаза»: модератор контролирует ввод]
              │
              v
[5. exit / kill-switch → закрытие сессии]
              │
              v
[6. JIT-отзыв прав + SHA-256 лога → тикет + SIEM]
```

---

## Матрица соответствия: этап регламента → контроль продукта

| Этап регламента | Технический контроль MT: Bastion | Компонент |
| :--- | :--- | :--- |
| 1.3 JIT whitelist | `bastion_operators`, `permit_open`, `ansible-playbook` | `group_vars/all.yml`, `site.yml` |
| 2.1 SSH-ключ | `authorized_keys` (+ `restrict` для jump) | `templates/authorized_keys.j2` |
| 2.2 TOTP | PAM, `MFA_STRICT=1` | `build/Containerfile`, preflight |
| 3.2 Append-only лог | `script` + `chattr +a` на `.log`; каталог `0750` | `bastion-shell-wrapper.sh`, `bastion-entrypoint.sh`, `prepare_os.yml` |
| 2.1 SSH User CA (опц.) | `bastion_trusted_user_ca_file`, operator `certificate` | `templates/sshd_config.j2`, `templates/authorized_keys.j2` |
| 5.2 JIT-отзыв | `valid_until` + jit_filter + purge + timer | `tasks/jit_filter_operators.yml`, `tasks/jit_purge.yml` |
| 4.3 Kill-switch | `podman stop mt_ssh_bastion` | Runbook §7 Whitepaper |
| 5.3 Аудит | auditd + session logs + SHA-256 sidecar | `auditd-bastion.rules.j2`, `bastion-shell-wrapper.sh` |

---

## Роли и ответственность

| Роль | Ответственность |
| :--- | :--- |
| **Инженер MT Global** | Работа строго в рамках тикета и окна доступа; соблюдение режима read-only до делегирования |
| **ИБ-модератор Заказчика** | Контроль ввода, инициация/завершение tmux-моста, ProxyJump к внутренним системам |
| **CSO / офицер ИБ Заказчика** | Одобрение JIT-окна, whitelist, приёмка аудиторского следа |
| **Администратор Ansible** | Декларативное применение `bastion_operators` и отзыв прав по окончании окна |

---

## Audit-Safe формулировки

| Избегать | Говорить |
| :--- | :--- |
| «Инженер физически не может ввести опасную команду» | «Модератор видит ввод в реальном времени и может мгновенно прервать сессию; все действия записываются в append-only лог» |
| «Tmux гарантирует блокировку rm -rf» | «Tmux — инструмент dual custody; блокировка деструктивных команд обеспечивается совокупностью модерации, whitelist и процедур Заказчика» |
| «Доступ автоматически отзывается через 2 часа» | «Окно доступа ограничено регламентом; отзыв прав выполняется декларативно через Ansible по согласованному SLA» |

---

*MT Global — MT: Bastion Troubleshooting Workflow v1.4.*
