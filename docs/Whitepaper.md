# ТЕХНИЧЕСКИЙ ПАСПОРТ ПРОДУКТА (WHITEPAPER)

## Архитектура и защитные контроли шлюза удаленного доступа «SSH PAM»

**Версия документа:** 1.8  
**Статус:** Релиз (Tier 5 FIDO-Anchor — v1.1.0)  
**Продукт (git tags):** `v1.1.0` — см. § «Версии релиза»  
**Разработчик:**   

---

## Версии релиза

| Git tag | Содержание | Статус |
| :--- | :--- | :--- |
| **v0.1** | Baseline: Policy Gate, MFA, declarative revoke, test-repo-key | ✅ |
| **v0.2.0** | **Phase A:** compliance verify, tamper-evident logs, source IP, SIEM forward, WORM | ✅ |
| **v0.4.0** | **Tier 1 Phase B + C:** JIT windows, SSH User CA prod policy | ✅ |
| **v0.5.0** | **Tier 2:** incident naming, denylist, audit role, rate limit, break-glass | ✅ |
| **v0.6.0** | **Tier 3:** SSH gateway, target recording, session-ctl, jump/gateway policy | ✅ |
| **v1.0.0** | **Tier 4:** session search, policy v2, live watch, Vault, OIDC examples, HA runbook | ✅ |
| **v1.1.0** | **Tier 5:** FIDO-Anchor MFA (`ed25519-sk` + TOTP), JIT cert signing for sk keys | ✅ |
| **Org gate** | Live PKI QA + `bastion_ssh_user_ca_qa_complete: true` on internal prod | ⏳ org |

Спецификации: `openspec/specs/`. История changes: `openspec/changes/archive/`. Краткий индекс кода: [docs/README.md](./README.md).

### Вне репозитория (организационно)

- Получить `user-ca.pub`, прогнать QA deploy и acceptance scenarios (`openspec/changes/archive/2026-06-ssh-user-ca-qa/tasks.md` §3–5).
- На prod клиента: включить opt-in при необходимости — `bastion_jit_timer_enabled`, `bastion_siem_forward_enabled`, `bastion_worm_archive_dir`.

---

## 1. Executive Summary (Общее описание)

**SSH PAM** — open-source tier продукта **SSH PAM**: полноценный **SSH PAM** (Privileged Access Management) в модели *Security-as-a-Code*. Заменяет коммерческий PAM-шлюз для Linux: контролируемый, изолированный и полностью аудируемый доступ инженеров поддержки во внутренний периметр заказчика.

Решение спроектировано по методологии **Zero Trust (микросегментация на уровне сессий)** и ориентировано на развёртывание в изолированных, критических и **Air-Gapped** контурах без необходимости прямого доступа к сети Интернет на этапе эксплуатации.

### Ключевые архитектурные вехи

- **Полная декларативность:** развёртывание, конфигурация и управление доступом осуществляются через идемпотентные сценарии Ansible.
- **Вендор-агностичность:** сквозной триггер `is_commercial_pam` позволяет переключать контур авторизации с open-source стека на промышленное коммерческое ПО (PAM-системы) без изменения логики деплоя.
- **Изоляция рантайма:** исключено использование привилегированного контекста внутри контейнера. Шлюз функционирует в Rootless Podman под непривилегированным пользователем хоста `bastion`.
- **FIDO-Anchor MFA (v1.1):** prod рекомендует **client-side** `ed25519-sk -O verify-required` (Touch ID / YubiKey) как первый фактор + **offline TOTP** на шлюз; без WebAuthn в контейнере и без proprietary client.

### Системные требования (хост шлюза)

- **Обязательная ОС хоста:** Rocky Linux 9.x (Enterprise LTS), архитектура x86_64.

> Решение CSO: другие дистрибутивы, архитектуры и режимы SELinux **не поддерживаются** и блокируются preflight-проверкой плейбука (`tasks/preflight_cso.yml`).

Rocky Linux 9 — единственная утверждённая платформа по следующим причинам:

1. **Родной Podman** — в семействе RHEL Podman интегрирован на уровне системных утилит и из коробки поддерживает Rootless-режим без сторонних обёрток (в отличие от Ubuntu, где по умолчанию доминирует Docker/Snap).
2. **SELinux** — при монтировании томов с флагом `:Z` (реализовано в плейбуке) процессы контейнера жёстко изолируются от хоста штатными политиками без разработки custom MAC-правил.
3. **Жизненный цикл** — Rocky Linux 9 получает патчи безопасности до **мая 2032 года**, что снижает риск преждевременного вывода шлюза из эксплуатации по причине EOL ОС.

### Решения CSO (Policy Gate)

| # | Решение | Статус |
| :-: | :--- | :--- |
| 1 | Хост: **только** Rocky Linux 9.x, **x86_64** | Обязательно, preflight |
| 2 | SELinux: **Enforcing** | Обязательно, preflight |
| 3 | Контейнерный движок: **Rootless Podman** (Docker запрещён) | Обязательно |
| 4 | MFA: образ только с **MFA_STRICT=1** (`nullok` запрещён в prod) | Обязательно |
| 5 | Jump-host: **whitelist `PermitOpen`** (пустой список = stop deploy) | Обязательно |
| 6 | Операторы: явный список `bastion_operators` до деплоя | Обязательно |
| 7 | Управление доступом: **только Ansible** (ручные правки на хосте запрещены) | Runbook |
| 8 | Firewall хоста: **firewalld** (штатный стек RHEL) | Обязательно |
| 9 | Jump-оператор: **restrict + port-forwarding** в `authorized_keys` | Обязательно |
| 10 | Образ: OCI-label **bastion.mfa.strict=1** (verify после load) | Обязательно |
| 11 | Роль `access: shell` — только по согласованию CSO заказчика | Организационно |
| 12 | **SSH User CA** (`bastion_trusted_user_ca_file`, operator `certificate`) | Prod policy: `bastion_allow_raw_pubkey_prod`; signing offline — `scripts/sign-operator-cert.sh.example` |
| 13 | **Declarative revoke операторов** | Удаление из `bastion_operators` → purge каталогов, MFA, Unix-учёток в контейнере + restart | `tasks/purge_revoked_operators.yml` |
| 14 | **Source IP restriction** (`allowed_sources`, опц. `bastion_allowed_source_cidrs`) | Per-operator `from=`; strict mode: `bastion_require_source_ip` | `templates/authorized_keys.j2`, `tasks/configure_source_firewall.yml` |
| 15 | **Tamper-evident session logs** | SHA-256 sidecar + `.meta` при закрытии shell-сессии | `build/files/bastion-shell-wrapper.sh` |
| 16 | **SIEM syslog forward** | auditd → LOCAL6 → rsyslog → client SIEM (opt-in) | `tasks/configure_rsyslog_siem.yml` |
| 17 | **Compliance verify** | Post-deploy checks (Rocky 9, SELinux, container, auditd…) | `scripts/bastion-compliance-verify.sh`, `tasks/verify_compliance_cso.yml` |
| 18 | **WORM archive session logs** | Копирование закрытых `.log` + sidecars на WORM mount | `tasks/archive_session_logs_worm.yml` |
| 19 | **JIT access windows** | `valid_from` / `valid_until` + auto-purge; опц. systemd timer | `tasks/jit_filter_operators.yml`, `tasks/configure_jit_timer.yml` |
| 20 | **SSH User CA prod** | Certificates ≤72h; raw pubkey blocked без waiver | `bastion_allow_raw_pubkey_prod`, `scripts/sign-operator-cert.sh.example` |
| 21 | **Incident log naming (Tier 2)** | `incident_id` в basename `session_<INCIDENT>_<USER>_…` | `build/files/bastion-shell-wrapper.sh` |
| 22 | **Shell command denylist (Tier 2)** | Denylist RO `/etc/bastion/command_denylist`; **prod: enforcement v2** (PTY inspector) | `bastion-pty-inspector.py`, `bastion-command-policy.sh` (v1 migration-only) |
| 23 | **Audit readonly role (Tier 2)** | `access: audit` — чтение `/var/log/bastion_sessions` без jump | `bastion-audit-shell-wrapper.sh`, `templates/sshd_config.j2` |
| 24 | **SSH brute-force protection (Tier 2)** | firewalld rate limit (default) или opt-in fail2ban | `tasks/configure_ssh_brute_force.yml` |
| 25 | **Break-glass emergency access (Tier 2)** | `break_glass: true` + JIT window ≤ max hours; auditd + syslog markers | `preflight_cso.yml`, `templates/auditd-bastion.rules.j2` |
| 26 | **SSH gateway access (Tier 3)** | `access: gateway` — SSH с шлюза, full target PTY log | `bastion-ssh-gateway-wrapper.sh`, `tasks/provision_bastion_targets.yml` |
| 27 | **Target credential broking (Tier 3)** | `bastion_targets[]`; keys Vault-only; RO mount `/etc/bastion/targets` | `tasks/provision_bastion_targets.yml` |
| 28 | **Gateway session control (Tier 3)** | `bastion-session-ctl list|kill`; JIT purge kills active sessions | `scripts/bastion-session-ctl.sh`, `tasks/kill_gateway_sessions.yml` |
| 29 | **Session search (Tier 4)** | JSONL filter by operator/date; host CLI `bastion-session-search` | `scripts/bastion-session-search.sh`, `tasks/install_tier4_tools.yml` |
| 30 | **Live session moderation (Tier 4)** | `bastion-session-watch` tail + JSONL `moderator_watch_start` | `scripts/bastion-session-watch.sh` |
| 31 | **Gateway command policy v2 (Tier 4)** | **Обязателен в prod:** denylist на audit boundary шлюза (Python PTY inspector) | `bastion-pty-inspector.py`, `bastion-ssh-gateway-exec.sh` |
| 32 | **FIDO-Anchor operator keys (Tier 5)** | `ed25519-sk -O verify-required`; preflight + compliance `fido_pubkey` | `scripts/preflight-fido-key.py`, `bastion_require_fido_pubkey` |
| 33 | **MFA modes (Tier 5)** | `totp` / `fido_totp` (prod) / `fido_only` (CSO waiver only) | `bastion_mfa_mode`, `templates/sshd_config.j2` |
| 34 | **Command policy v2 mandatory** | При `bastion_shell_command_policy_enabled: true` — v2 включён; v1 только migration + `bastion_command_policy_v2_required: false` | `preflight_cso.yml`, `bastion-compliance-verify.sh` |

---

## 2. Модель угроз и границы доверия (Trust Boundaries)

Продукт «SSH PAM» исходит из предположения, что хостовая операционная система шлюза (DMZ) находится в зоне повышенного риска. Границы доверия жёстко разграничены.

```
[ НЕБЕЗОПАСНАЯ ЗОНА ]          [ ЗОНА КОНТРОЛЯ SSH PAM ]

Администратор         +---------------------------------------+
(SSH-ключ + Offline TOTP)      | Rocky Linux 9.x (x86_64)              |
         |                     |  --> firewalld (порт 2222)            |
         v                     |  --> SELinux (:Z на томах Podman)     |
[ Внешний интерфейс ] -------->|  --> auditd (контроль ядра хоста)     |
                               |  +-------------------------------+  |
                               |  | Rootless Podman Container     |  |
                               |  | (пользователь: bastion)    |  |
                               |  |  --> ограниченный sshd        |  |
                               |  +-------------------------------+  |
                               +---------------------------------------+
                                         |
                                         v
                               [ Gateway SSH → target Linux ]
                               (PTY log на шлюз; jump — PermitOpen only)
```

### Нейтрализуемые векторы атак

1. **Компрометация SSH-демона (0-day):** эксплуатация уязвимости внутри контейнера не позволяет злоумышленнику получить права `root` на хосте, так как процесс запущен в Rootless-режиме (UID сопоставлен с непривилегированным пользователем `bastion`).
2. **Компрометация учётной записи оператора:** перехват файла приватного ключа недостаточен — требуется **FIDO user verification** на устройстве (sk key, Tier 5) и **offline TOTP** на шлюз (или CSO-waiver `fido_only`).
3. **Модификация логов правонарушителем:** попытка очистить историю команд блокируется системным атрибутом `Append-Only` (`chattr +a`) на уровне хостовой ОС в момент создания лог-файла.

---

## 3. Роли доступа и запись сессий

| `access` | Назначение | Запись PTY |
| :--- | :--- | :---: |
| `gateway` | **Prod:** интерактив на Linux-target через шлюз | ✅ на target |
| `jump` | ProxyJump / automation; connect-audit | ❌ |
| `shell` | Работа на шлюзе, four-eyes | ✅ шлюз |
| `audit` | Чтение логов, `bastion-session-watch` | read-only |

Полная матрица контролей — **Policy Gate** (§ выше, #1–33).

---

## 4. Сценарии доступа (Workflow)

Доступ операторов разграничен на прикладном уровне OpenSSH. Шлюз поддерживает **четыре** режима: `jump`, `gateway`, `shell`, `audit`.

### Сценарий А: интерактивный Shell-доступ (`access: shell`)

Предназначен для локальной работы на шлюзе или инициирования сессий совместного траблшутинга (принцип «четырёх глаз»).

1. Оператор авторизуется (SSH-ключ + TOTP).
2. Вызывается `ForceCommand /usr/local/bin/bastion-shell-wrapper.sh`.
3. Сессия оборачивается в утилиту `script`. Лог-файл создаётся на хосте и сразу получает атрибут `+a` (только дозапись).
4. Оператор может работать в `tmux`-сессии совместно с модератором заказчика.

### Сценарий Б: транзитный Jump-доступ (`access: jump`)

Предназначен для сквозного подключения (ProxyJump) к целевому оборудованию.

1. Штатный сценарий — ProxyJump (`ssh -J`), без интерактивной работы на шлюзе.
2. Прямой shell-login для jump-оператора **заблокирован** опциями `restrict,port-forwarding` в `authorized_keys`.
3. Разрешён только контролируемый TCP-forwarding через `PermitOpen` на явно заданные целевые хосты и порты.
4. Сетевые события фиксируются средствами `LogLevel VERBOSE` OpenSSH и правилами `auditd` на хосте.

> **Примечание для аудита:** прикладной слой `PermitOpen` дополляет, но не заменяет сетевую сегментацию (firewall / security groups) на стороне заказчика.

### Сценарий В: SSH Gateway (`access: gateway`)

1. ForceCommand `bastion-ssh-gateway-wrapper.sh`; target из `permit_open`.
2. Gateway SSH к target с broked key; оператор ключ target не получает.
3. Лог `gateway_*` + sidecars + JSONL.
4. `bastion-session-ctl list|kill`.
5. **Tier 4:** `bastion-session-search`, `bastion-session-watch` (moderator), command policy v2 on PTY stream.

См. [SSH-PAM-Overview.md](./SSH-PAM-Overview.md).


---

## 5. Порядок развёртывания и Onboarding MFA в Air Gap

Процесс деплоя автономен и разделён на две фазы для соблюдения регламентов закрытого контура.

### Фаза 1: подготовка на доверенной build-машине (с доступом в сеть)

1. Выполняется `./trusted_download.sh` (по умолчанию `MFA_STRICT=1`).
2. Скрипт собирает immutable-образ из декларативного `build/Containerfile`, экспортирует tar-архив (`bastion_image.tar`) и формирует файл контрольных сумм `SHA256SUMS`.
3. Артефакты передаются в закрытый контур по регламенту заказчика. На целевом хосте выполняется проверка: `sha256sum -c SHA256SUMS`.

### Фаза 2: деплой в закрытом контуре клиента (Air Gap)

1. Tar-архив и репозиторий `pam/` переносятся на хост назначения.
2. В `group_vars/all.yml` заполняется массив `bastion_operators` (см. `group_vars/all.yml.example`).
3. Запускается `ansible-galaxy collection install -r requirements.yml`, затем `ansible-playbook site.yml`.
4. Preflight CSO проверяет Rocky Linux 9, x86_64, SELinux Enforcing, whitelist и операторов. При нарушении — **деплой прерывается**.
5. Плейбук: preflight → prepare → **purge отозванных** → provision операторов → deploy (`podman load`, verify label, start container).
6. **Важно:** TOTP-секреты → `generated/mfa/<host>/<user>.mfa.txt` на контроллере Ansible. Передать операторам **до** первой сессии. Каталог `generated/` не коммитить.

### Onboarding MFA

TOTP-секреты генерируются плейбуком и передаются операторам **до** первого входа. Сборка образа с `MFA_STRICT=0` допускается **только** в lab-контуре (`BASTION_LAB_MODE=1`) и **запрещена** для production-деплоя.

---

## 6. Комплаенс и регуляторные ограничения (Audit-Safe Disclaimer)

Архитектура «SSH PAM» спроектирована с учётом технических требований стандартов **PCI-DSS 4.0** (разделы 8.3/8.4 — MFA, раздел 10 — аудит) и руководящих документов по защите **КИИ** и **СТО БР ИББС**.

### Важное ограничение для аудита

Продукт «SSH PAM» является техническим инструментом контроля (Security Control) и базой для построения защищённого процесса. Финальное соответствие (Compliance) инфраструктуры заказчика регуляторным требованиям зависит от смежных организационных политик на стороне клиента, включая:

- настройку ротации SSH-ключей и TOTP-секретов операторов;
- интеграцию хостового `auditd` и syslog с корпоративной SIEM;
- политику долгосрочного хранения (retention) файлов аудита сессий на внешних WORM-хранилищах;
- сетевую сегментацию DMZ и мониторинг исходящих соединений с шлюза.

### SIEM forwarder (опционально)

При `bastion_siem_forward_enabled: true` плейбук разворачивает:

1. **auditd plugin** → syslog facility `LOCAL6` (`/etc/audit/plugins.d/syslog.conf`).
2. **rsyslog drop-in** → `@@<bastion_siem_server>:514` (`templates/rsyslog-bastion-siem.conf.j2`).

Переменные: `bastion_siem_server`, `bastion_siem_port`, `bastion_siem_protocol` (`tcp` | `udp` | `relp`).

Нормализация в CEF/JSON — **на стороне SIEM заказчика** (см. OpenSpec `bastion-siem-syslog-export`). SSH PAM не отправляет данные в облако .

Проверка после деплоя:

```bash
ansible-playbook site.yml --tags verify_compliance
./scripts/bastion-compliance-verify.sh
```

---

## 7. Operational Runbook (Операционные регламенты)

> Полный сквозной воркфлоу инцидента (JIT, four-eyes, архивация): [Troubleshooting-Workflow.md](./Troubleshooting-Workflow.md)

### Добавление / отзыв прав оператора

Исключительно через редактирование массива `bastion_operators` в Ansible с последующим перевыпуском `ansible-playbook site.yml`. Ручные правки на хосте или в контейнере запрещены — будут перезаписаны или удалены при sync.

**Отзыв (JIT offboarding):**

1. Удалить оператора из `bastion_operators` (prod) или из `group_vars/dev/test_operators.yml` (lab).
2. Запустить `ansible-playbook site.yml`.
3. Плейбук выполняет `tasks/purge_revoked_operators.yml`:
   - удаляет `{{ operators_home }}/<name>/` на хосте;
   - удаляет `generated/mfa/<host>/<name>.mfa.txt`;
   - удаляет Unix-учётку и `/home/<name>` в контейнере;
   - перезапускает `ssh_bastion` (handler `Restart ssh gateway container`).

**Dev shortcut:** `./scripts/test-repo-key.sh revoke <name> --apply`

### JIT access windows (valid_until)

Оператору можно задать временное окно в `bastion_operators`:

```yaml
valid_from: "2026-06-15T09:00:00+03:00"
valid_until: "2026-06-15T18:00:00+03:00"
incident_id: "INC-2026-8942"
```

При каждом `ansible-playbook site.yml` (или `--tags jit_purge`) плейбук:

1. Фильтрует истёкших / ещё не активных операторов (`tasks/jit_filter_operators.yml`).
2. Выполняет purge + restart контейнера (как при ручном отзыве).

**Автоматизация на хосте:** `bastion_jit_timer_enabled: true` — systemd timer (hourly по умолчанию).  
Скрипт: `scripts/jit-purge-host.sh.example` → `bastion_jit_playbook_command`.

> Активная SSH-сессия может сохраняться до disconnect; новые логины блокируются после purge.

### Ротация SSH User CA certificates (prod)

1. Сгенерировать ключ оператора локально (`ssh-keygen -t ed25519`).
2. Подписать на **offline** станции: `scripts/sign-operator-cert.sh.example` (≤ `bastion_cert_max_validity_hours`, default 72).
3. Положить `*-cert.pub` в secure path; обновить `operator.certificate` в Vault/group_vars.
4. `ansible-playbook site.yml` — hot reload через handler.
5. После QA: `bastion_ssh_user_ca_qa_complete: true`, `bastion_allow_raw_pubkey_prod: false`.

**Rollback:** убрать `bastion_trusted_user_ca_file`, вернуть `pubkey`, redeploy — без пересборки образа.

### OIDC / SAML → SSH user certificates (Tier 4, opt-in)

1. IdP group `bastion-operators` (или `bastion_oidc_required_group`).
2. Offline token: `scripts/oidc-offline-token.sh.example`.
3. Sign cert: `scripts/sign-operator-cert-oidc.sh.example` (bridge к org User CA).
4. SAML stub: `scripts/sign-operator-cert-saml.sh.example` → OIDC bridge.
5. Prod gate: `bastion_oidc_cert_policy_enabled: true` — preflight требует `certificate` у операторов.

См. также `openspec/specs/bastion-oidc-saml-ssh-certificates/spec.md`.

### Ротация ключей и TOTP

- **SSH-ключ:** обновить поле `pubkey` оператора, перевыпустить плейбук.
- **TOTP:** удалить `.google_authenticator` оператора в `{{ bastion_home }}/operators/<name>/`, очистить или задать новый `mfa_secret`, перевыпустить плейбук. Новый секрет — из `generated/mfa/`.

### Действия при инциденте

При подозрительной активности (алерт `auditd`, SIEM):

```bash
sudo -u bastion podman stop ssh_bastion
```

Контейнер останавливается, активные сессии разрываются. Логи сессий на хостовой ОС сохраняются для расследования.

### Переключение на коммерческий PAM

Установить `is_commercial_pam: true`, задать `commercial_pam_api_url` и `commercial_pam_api_token` (Vault). Open-source компоненты не разворачиваются.

---

## 8. Audit-Safe речевые модули для встречи с CSO

Используйте формулировки ниже, чтобы продемонстрировать понимание ИБ-архитектуры и избежать overclaim.

| Избегать | Говорить |
| :--- | :--- |
| «Наш шлюз на 100% гарантирует, что инженер ничего не сломает в вашей сети» | «Архитектура поддерживает принцип наименьших привилегий через прикладную микросегментацию. Инженер изолирован настройкой `PermitOpen` — доступ только к явно одобренным хостам и портам, без неконтролируемого форвардинга и сканирования подсетей» |
| «Решение полностью сертифицировано по КИИ и PCI-DSS» | «Технические контроли шлюза (локальный MFA, изоляция рантайма, append-only логирование) спроектированы в соответствии с требованиями PCI-DSS 4.0 и руководящих документов по защите КИИ, что упрощает прохождение регулярного ИБ-аудита вашей инфраструктуры» |
| «Логи абсолютно невозможно удалить» | «At-birth protection: каждый лог-файл получает `chattr +a` в момент создания; каталог `/var/log/bastion_sessions` принадлежит `bastion` с правами `0750`. Рекомендуем стриминг `auditd` в SIEM» |
| «Jump-оператор не получит shell ни при каких условиях» | «Для роли jump в `authorized_keys` включён `restrict,port-forwarding` — PTY и shell заблокированы на уровне OpenSSH. Доступен только audited ProxyJump к whitelist-хостам» |

---

## 9. Checklist готовности инфраструктуры клиента

Используйте перед пресейлом и kick-off деплоя.

### Целевой хост шлюза

| # | Требование | Проверка |
| :-: | :--- | :--- |
| 1 | **Обязательная ОС хоста:** Rocky Linux 9.x (Enterprise LTS), x86_64 | `cat /etc/os-release` |
| 2 | SELinux **Enforcing** (иначе preflight fail) | `getenforce` |
| 3 | Rootless Podman | `podman info --format '{{.Host.Security.Rootless}}'` |
| 4 | Минимум 2 vCPU, 4 GB RAM, 20 GB disk | `nproc`, `free -h`, `df -h` |
| 5 | Размещение в DMZ / изолированном сегменте | Согласование с сетевой командой клиента |
| 6 | Статический IP или DNS-имя для inventory Ansible | `inventory/hosts.yml` |
| 7 | SSH-доступ Ansible-контроллера к хосту (sudo) | `ansible bastion_servers -m ping` |
| 8 | Preflight CSO пройден | `ansible-playbook site.yml` (без fail на preflight) |

### Пакеты (устанавливаются плейбуком на Rocky Linux 9)

| Компонент | Пакеты |
| :--- | :--- |
| Rootless Podman | `podman`, `slirp4netns`, `fuse-overlayfs` |
| Аудит | `audit` (auditd) |
| Firewall | `firewalld` |
| MAC | `selinux-policy-targeted` (предустановлен в Rocky Linux 9) |

### Уровни зависимостей (CSO)

Зависимости разделены по границе доверия — не смешивать в onboarding оператора.

| Уровень | Где | Обязательно | Примеры |
| :--- | :--- | :---: | :--- |
| **A — Prod runtime** | Rocky host + образ шлюза | Да | Podman, OpenSSH/PAM, `google-authenticator`, `python3` (PTY inspector v2), `e2fsprogs` (`chattr`) |
| **B — Deploy plane** | Build/deploy host | Да для деплоя | Ansible, `containers.podman`, `ansible.posix`; `community.hashi_vault` — только при `bastion_vault_enabled` |
| **C — Host tools (opt-in)** | Rocky host | По фичам | `jq` при `bastion_session_search_enabled`; fail2ban/rsyslog — opt-in |
| **D — Lab / operator UX** | Ноутбук инженера | Нет для prod | Lima, `dev-up`, `bastion-doctor`, Node/QR — вне security boundary |

**Оператор prod:** только `ssh` + Authenticator. Всё из уровня D — админ/lab, не требование доступа.

### Build-машина (фаза 1, вне Air Gap)

| # | Требование |
| :-: | :--- |
| 1 | Podman установлен |
| 2 | Доступ к базовому образу `alpine:3.19` (или предзагруженный mirror) |
| 3 | Выполнен `./trusted_download.sh`, получены `bastion_image.tar` и `SHA256SUMS` |
| 4 | Артефакты переданы в контур клиента с сохранением контрольной суммы |

### Управляющая машина Ansible

| # | Требование |
| :-: | :--- |
| 1 | Ansible 2.14+ |
| 2 | Коллекции: `containers.podman`, `ansible.posix` (Vault: `community.hashi_vault` — только при `bastion_vault_enabled`) |
| 3 | Заполнены `bastion_operators` и `bastion_permitted_targets` |
| 4 | Секреты (`mfa_secret`, `commercial_pam_api_token`) — в Ansible Vault |
| 5 | Каталог `generated/mfa/` защищён правами `0700`, не в git |

### Сеть и доступ

| # | Требование |
| :-: | :--- |
| 1 | Порт `bastion_ssh_port` (по умолчанию 2222) открыт только для доверенных источников |
| 2 | Список целей `PermitOpen` согласован с владельцами систем (формат `host:port`, без CIDR) |
| 3 | Маршрутизация с шлюза до целевых хостов проверена (`nc -zv target 22`) |
| 4 | SIEM-команда клиента уведомлена о правилах `auditd` (`bastion_session_logs`, `bastion_ssh_connect`) |
| 5 | При SIEM forward: `bastion_siem_server` доступен по TCP/RELP из DMZ |
| 6 | Compliance verify: `./scripts/bastion-compliance-verify.sh` exit 0 после деплоя |

### Dev / lab (инженеры )

| # | Требование |
| :-: | :--- |
| 1 | macOS/Linux с Lima, Podman, Ansible |
| 2 | `./scripts/dev-up.sh` — lab-ключи, Rocky 9 VM, образ, деплой |
| 3 | Операторы: `group_vars/dev/lab.yml` (не prod `all.yml`) |
| 4 | Inventory: `inventory/local-lima.yml` |
| 5 | Onboarding: [Engineer-Onboarding.md](./Engineer-Onboarding.md) |

### Перед первой рабочей сессией (prod)

| # | Требование |
| :-: | :--- |
| 1 | TOTP-секреты переданы операторам по доверенному каналу |
| 2 | Операторы импортировали TOTP в authenticator-приложение |
| 3 | Тестовый вход: `gateway` (prod), при необходимости `jump` / `shell` |
| 4 | Gateway: `gateway_*.log` + `sha256sum -c`; JSONL в `sessions.jsonl` |
| 5 | `bastion-session-search` / compliance verify exit 0 |
| 6 | Prod FIDO (рекомендуется): `ed25519-sk -O verify-required`; `bastion_require_fido_pubkey: true` |
| 7 | Образ `MFA_STRICT=1`; после wrapper — `./trusted_download.sh` |

---

## Приложение: ключевые пути

| Область | Пути |
| :--- | :--- |
| Deploy | `site.yml`, `tasks/preflight_cso.yml`, `tasks/deploy_ssh_bastion.yml` |
| Gateway | `build/files/bastion-ssh-gateway-*.sh`, `tasks/provision_bastion_targets.yml` |
| Policy | `group_vars/all.yml`, `group_vars/prod.yml.example`, `templates/sshd_config.j2` |
| CLI | `scripts/bastion-session-{ctl,search,watch}.sh`, `scripts/bastion-compliance-verify.sh` |
| FIDO | [FIDO-Onboarding.md](./FIDO-Onboarding.md), `scripts/preflight-fido-key.py` |
| Lab | `group_vars/dev/`, `inventory/local-lima.yml`, `./scripts/dev-up.sh` |
| Specs | `openspec/specs/`, `openspec/changes/archive/` |

---

*Документ подготовлен . Актуально для продукта **v1.1.0** (документ **1.8**).*
