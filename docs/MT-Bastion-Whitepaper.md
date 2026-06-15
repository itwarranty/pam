# ТЕХНИЧЕСКИЙ ПАСПОРТ ПРОДУКТА (WHITEPAPER)

## Архитектура и защитные контроли шлюза удаленного доступа «MT: Bastion»

**Версия документа:** 1.2  
**Статус:** Релиз (готов к пресейлу / ИБ-аудиту)  
**Разработчик:** MT Global  

---

## 1. Executive Summary (Общее описание)

**MT: Bastion** — отчуждаемое программное решение класса *Security-as-a-Code (SaaC)*, предназначенное для организации контролируемого, изолированного и полностью аудируемого удалённого доступа инженеров технической поддержки во внутренний периметр заказчика.

Решение спроектировано по методологии **Zero Trust (микросегментация на уровне сессий)** и ориентировано на развёртывание в изолированных, критических и **Air-Gapped** контурах без необходимости прямого доступа к сети Интернет на этапе эксплуатации.

### Ключевые архитектурные вехи

- **Полная декларативность:** развёртывание, конфигурация и управление доступом осуществляются через идемпотентные сценарии Ansible.
- **Вендор-агностичность:** сквозной триггер `is_commercial_pam` позволяет переключать контур авторизации с open-source стека на промышленное коммерческое ПО (PAM-системы) без изменения логики деплоя.
- **Изоляция рантайма:** исключено использование привилегированного контекста внутри контейнера. Бастион функционирует в Rootless Podman под непривилегированным пользователем хоста `mt_bastion`.

### Системные требования (хост бастиона)

- **Обязательная ОС хоста:** Rocky Linux 9.x (Enterprise LTS), архитектура x86_64.

> Решение CSO: другие дистрибутивы, архитектуры и режимы SELinux **не поддерживаются** и блокируются preflight-проверкой плейбука (`tasks/preflight_cso.yml`).

Rocky Linux 9 — единственная утверждённая платформа по следующим причинам:

1. **Родной Podman** — в семействе RHEL Podman интегрирован на уровне системных утилит и из коробки поддерживает Rootless-режим без сторонних обёрток (в отличие от Ubuntu, где по умолчанию доминирует Docker/Snap).
2. **SELinux** — при монтировании томов с флагом `:Z` (реализовано в плейбуке) процессы контейнера жёстко изолируются от хоста штатными политиками без разработки custom MAC-правил.
3. **Жизненный цикл** — Rocky Linux 9 получает патчи безопасности до **мая 2032 года**, что снижает риск преждевременного вывода бастиона из эксплуатации по причине EOL ОС.

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
| 10 | Образ: OCI-label **mt.global.mfa.strict=1** (verify после load) | Обязательно |
| 11 | Роль `access: shell` — только по согласованию CSO заказчика | Организационно |
| 12 | **SSH User CA** (`bastion_trusted_user_ca_file`, operator `certificate`) | Реализовано; prod rollout — OpenSpec `openspec/changes/ssh-user-ca-qa-mtglobal/` |
| 13 | **Declarative revoke операторов** | Удаление из `bastion_operators` → purge каталогов, MFA, Unix-учёток в контейнере + restart | `tasks/purge_revoked_operators.yml` |
| 14 | **Source IP restriction** (`allowed_sources`, опц. `bastion_allowed_source_cidrs`) | Per-operator `from=`; strict mode: `bastion_require_source_ip` | `templates/authorized_keys.j2`, `tasks/configure_source_firewall.yml` |
| 15 | **Tamper-evident session logs** | SHA-256 sidecar + `.meta` при закрытии shell-сессии | `build/files/bastion-shell-wrapper.sh` |
| 16 | **SIEM syslog forward** | auditd → LOCAL6 → rsyslog → client SIEM (opt-in) | `tasks/configure_rsyslog_siem.yml` |
| 17 | **Compliance verify** | Post-deploy checks (Rocky 9, SELinux, container, auditd…) | `scripts/bastion-compliance-verify.sh`, `tasks/verify_compliance_cso.yml` |
| 18 | **WORM archive session logs** | Копирование закрытых `.log` + sidecars на WORM mount | `tasks/archive_session_logs_worm.yml` |

---

## 2. Модель угроз и границы доверия (Trust Boundaries)

Продукт «MT: Bastion» исходит из предположения, что хостовая операционная система бастиона (DMZ) находится в зоне повышенного риска. Границы доверия жёстко разграничены.

```
[ НЕБЕЗОПАСНАЯ ЗОНА ]          [ ЗОНА КОНТРОЛЯ MT: BASTION ]

Администратор MT Global        +---------------------------------------+
(SSH-ключ + Offline TOTP)      | Rocky Linux 9.x (x86_64)              |
         |                     |  --> firewalld (порт 2222)            |
         v                     |  --> SELinux (:Z на томах Podman)     |
[ Внешний интерфейс ] -------->|  --> auditd (контроль ядра хоста)     |
                               |  +-------------------------------+  |
                               |  | Rootless Podman Container     |  |
                               |  | (пользователь: mt_bastion)    |  |
                               |  |  --> ограниченный sshd        |  |
                               |  +-------------------------------+  |
                               +---------------------------------------+
                                         |
                                         v
                               [ Внутренний периметр заказчика ]
                               (только PermitOpen host:port)
```

### Нейтрализуемые векторы атак

1. **Компрометация SSH-демона (0-day):** эксплуатация уязвимости внутри контейнера не позволяет злоумышленнику получить права `root` на хосте, так как процесс запущен в Rootless-режиме (UID сопоставлен с непривилегированным пользователем `mt_bastion`).
2. **Компрометация учётной записи оператора:** перехват приватного SSH-ключа недостаточен для входа из-за обязательной валидации второго фактора MFA (локальный TOTP через PAM).
3. **Модификация логов правонарушителем:** попытка очистить историю команд блокируется системным атрибутом `Append-Only` (`chattr +a`) на уровне хостовой ОС в момент создания лог-файла.

---

## 3. Матрица защитных контролей (Control Matrix)

Таблица сопоставляет требования ИБ-стандартов с технической реализацией в кодовой базе `mt-bastion/`.

| ИБ-требование | Техническая реализация в MT: Bastion | Файл / компонент |
| :--- | :--- | :--- |
| **Изоляция процессов и минимизация привилегий** | Запуск контейнера без root на хосте. Systemd lingering для персистентности процессов без интерактивного входа root. | `tasks/prepare_os.yml`, `tasks/deploy_ssh_bastion.yml` (`become_user: mt_bastion`) |
| **MAC-изоляция контейнера (SELinux)** | Метки томов `:Z` при монтировании. Каталоги операторов — `container_file_t` (`setype` + `chcon`). Preflight блокирует деплой при SELinux ≠ Enforcing. | `tasks/preflight_cso.yml`, `tasks/provision_operator_item.yml`, `tasks/deploy_ssh_bastion.yml` |
| **Policy Gate (Preflight CSO)** | Автоматическая блокировка деплоя на неподдерживаемой ОС, архитектуре, без whitelist или без операторов. | `tasks/preflight_cso.yml` |
| **Jump без shell (restrict keys)** | `restrict,port-forwarding,permitopen=...` в `authorized_keys` для `access: jump`. Прямой PTY/shell невозможен. | `templates/authorized_keys.j2` |
| **Верификация supply chain образа** | OCI-label `mt.global.mfa.strict=1` проверяется после `podman load`. | `tasks/verify_image_cso.yml`, `build/Containerfile` |
| **Provisioning операторов (immutable mount)** | Конфиги операторов на хосте (`operators_home`) монтируются read-only в `/etc/bastion/operators`; entrypoint копирует в `/home/<user>` при старте. | `tasks/provision_operator_item.yml`, `build/files/bastion-entrypoint.sh`, `tasks/deploy_ssh_bastion.yml` |
| **SSH User CA (опционально)** | `TrustedUserCAKeys` + operator `certificate` вместо raw `pubkey`. | `templates/sshd_config.j2`, `templates/authorized_keys.j2`, `bastion_trusted_user_ca_file` |
| **Строгая двухфакторная аутентификация (MFA)** | Локальный PAM-модуль TOTP. Режим `MFA_STRICT=1` по умолчанию. Запрет паролей. | `build/Containerfile`, `templates/sshd_config.j2` (`AuthenticationMethods`) |
| **Защита цепочки поставок (Supply Chain)** | Исключение рантайм-загрузок пакетов (`apk add` при старте). Сборка immutable-образа на build-машине. Верификация SHA-256 артефакта перед деплоем. | `trusted_download.sh`, `build/Containerfile` |
| **Микросегментация (Least Privilege)** | Ограничение ProxyJump только до разрешённых `host:port` через `PermitOpen`. Персональные списки `permit_open` на оператора. | `templates/sshd_config.j2`, `group_vars/all.yml` |
| **Неотчуждаемый аудит и логирование** | Перехват shell-сессий через `script`, запись TTY-потока. Каталог логов `0750` (владелец `mt_bastion`). `chattr +a` на каждый `.log` при создании (wrapper + entrypoint). | `build/files/bastion-shell-wrapper.sh`, `build/files/bastion-entrypoint.sh`, `tasks/prepare_os.yml` |
| **Declarative revoke (JIT offboarding)** | Операторы вне `bastion_operators` удаляются с хоста, из `generated/mfa/`, из контейнера (`deluser`); handler перезапускает `mt_ssh_bastion`. Entrypoint дублирует purge при старте. | `tasks/purge_revoked_operators.yml`, `site.yml` (handler), `bastion-entrypoint.sh` |
| **Hot reload конфигурации** | Изменения `sshd_config`, ключей или TOTP → `podman restart mt_ssh_bastion` без полного redeploy. | `tasks/deploy_ssh_bastion.yml`, `tasks/provision_operator_item.yml` |
| **Контроль целостности бастиона** | Мониторинг записи в каталог логов и сетевых connect-событий на уровне ядра хоста. | `templates/auditd-bastion.rules.j2` |
| **Source IP restriction (Tier 1)** | Per-operator `from="CIDR,..."` в `authorized_keys`; опционально firewalld rich rules. | `templates/authorized_keys.j2`, `tasks/configure_source_firewall.yml`, `tasks/preflight_cso.yml` |
| **Tamper-evident session logs (Tier 1)** | При закрытии shell-сессии: GNU `.sha256` для `sha256sum -c` + `.meta` (UTC, USER, INCIDENT, CLIENT). | `build/files/bastion-shell-wrapper.sh` |
| **SIEM syslog export (Tier 1)** | auditd plugin LOCAL6 + rsyslog drop-in → client SIEM (TCP/UDP/RELP). | `tasks/configure_rsyslog_siem.yml`, `templates/rsyslog-bastion-siem.conf.j2` |
| **Compliance verify (Tier 1)** | Автоматическая проверка post-deploy; exit 0/non-zero для аудита и мониторинга. | `scripts/bastion-compliance-verify.sh`, tag `verify_compliance` |
| **WORM archive (Tier 1, опц.)** | Копирование закрытых логов на client WORM mount. | `tasks/archive_session_logs_worm.yml` |

---

## 4. Сценарии доступа (Workflow)

Доступ операторов разграничен на прикладном уровне OpenSSH. Бастион поддерживает два режима работы.

### Сценарий А: интерактивный Shell-доступ (`access: shell`)

Предназначен для локальной работы на бастионе или инициирования сессий совместного траблшутинга (принцип «четырёх глаз»).

1. Оператор авторизуется (SSH-ключ + TOTP).
2. Вызывается `ForceCommand /usr/local/bin/bastion-shell-wrapper.sh`.
3. Сессия оборачивается в утилиту `script`. Лог-файл создаётся на хосте и сразу получает атрибут `+a` (только дозапись).
4. Оператор может работать в `tmux`-сессии совместно с модератором заказчика.

### Сценарий Б: транзитный Jump-доступ (`access: jump`)

Предназначен для сквозного подключения (ProxyJump) к целевому оборудованию.

1. Штатный сценарий — ProxyJump (`ssh -J`), без интерактивной работы на бастионе.
2. Прямой shell-login для jump-оператора **заблокирован** опциями `restrict,port-forwarding` в `authorized_keys`.
3. Разрешён только контролируемый TCP-forwarding через `PermitOpen` на явно заданные целевые хосты и порты.
4. Сетевые события фиксируются средствами `LogLevel VERBOSE` OpenSSH и правилами `auditd` на хосте.

> **Примечание для аудита:** прикладной слой `PermitOpen` дополляет, но не заменяет сетевую сегментацию (firewall / security groups) на стороне заказчика.

---

## 5. Порядок развёртывания и Onboarding MFA в Air Gap

Процесс деплоя автономен и разделён на две фазы для соблюдения регламентов закрытого контура.

### Фаза 1: подготовка на доверенной build-машине (с доступом в сеть)

1. Выполняется `./trusted_download.sh` (по умолчанию `MFA_STRICT=1`).
2. Скрипт собирает immutable-образ из декларативного `build/Containerfile`, экспортирует tar-архив (`mt_bastion_image.tar`) и формирует файл контрольных сумм `SHA256SUMS`.
3. Артефакты передаются в закрытый контур по регламенту заказчика. На целевом хосте выполняется проверка: `sha256sum -c SHA256SUMS`.

### Фаза 2: деплой в закрытом контуре клиента (Air Gap)

1. Tar-архив и репозиторий `mt-bastion/` переносятся на хост назначения.
2. В `group_vars/all.yml` заполняется массив `bastion_operators` (см. `group_vars/all.yml.example`).
3. Запускается `ansible-galaxy collection install -r requirements.yml`, затем `ansible-playbook site.yml`.
4. Preflight CSO проверяет Rocky Linux 9, x86_64, SELinux Enforcing, whitelist и операторов. При нарушении — **деплой прерывается**.
5. Плейбук: preflight → prepare → **purge отозванных** → provision операторов → deploy (`podman load`, verify label, start container).
6. **Важно:** TOTP-секреты → `generated/mfa/<host>/<user>.mfa.txt` на контроллере Ansible. Передать операторам **до** первой сессии. Каталог `generated/` не коммитить.

### Onboarding MFA

TOTP-секреты генерируются плейбуком и передаются операторам **до** первого входа. Сборка образа с `MFA_STRICT=0` допускается **только** в lab-контуре (`BASTION_LAB_MODE=1`) и **запрещена** для production-деплоя.

---

## 6. Комплаенс и регуляторные ограничения (Audit-Safe Disclaimer)

Архитектура «MT: Bastion» спроектирована с учётом технических требований стандартов **PCI-DSS 4.0** (разделы 8.3/8.4 — MFA, раздел 10 — аудит) и руководящих документов по защите **КИИ** и **СТО БР ИББС**.

### Важное ограничение для аудита

Продукт «MT: Bastion» является техническим инструментом контроля (Security Control) и базой для построения защищённого процесса. Финальное соответствие (Compliance) инфраструктуры заказчика регуляторным требованиям зависит от смежных организационных политик на стороне клиента, включая:

- настройку ротации SSH-ключей и TOTP-секретов операторов;
- интеграцию хостового `auditd` и syslog с корпоративной SIEM;
- политику долгосрочного хранения (retention) файлов аудита сессий на внешних WORM-хранилищах;
- сетевую сегментацию DMZ и мониторинг исходящих соединений с бастиона.

### SIEM forwarder (Tier 1 Free, опционально)

При `bastion_siem_forward_enabled: true` плейбук разворачивает:

1. **auditd plugin** → syslog facility `LOCAL6` (`/etc/audit/plugins.d/syslog.conf`).
2. **rsyslog drop-in** → `@@<bastion_siem_server>:514` (`templates/rsyslog-bastion-siem.conf.j2`).

Переменные: `bastion_siem_server`, `bastion_siem_port`, `bastion_siem_protocol` (`tcp` | `udp` | `relp`).

Нормализация в CEF/JSON — **на стороне SIEM заказчика** (см. OpenSpec `bastion-siem-syslog-export`). MT: Bastion не отправляет данные в облако MT Global.

Проверка после деплоя:

```bash
ansible-playbook site.yml --tags verify_compliance
./scripts/bastion-compliance-verify.sh
```

---

## 7. Operational Runbook (Операционные регламенты)

> Полный сквозной воркфлоу инцидента (JIT, four-eyes, архивация): [MT-Bastion-Troubleshooting-Workflow.md](./MT-Bastion-Troubleshooting-Workflow.md)

### Добавление / отзыв прав оператора

Исключительно через редактирование массива `bastion_operators` в Ansible с последующим перевыпуском `ansible-playbook site.yml`. Ручные правки на хосте или в контейнере запрещены — будут перезаписаны или удалены при sync.

**Отзыв (JIT offboarding):**

1. Удалить оператора из `bastion_operators` (prod) или из `group_vars/dev/test_operators.yml` (lab).
2. Запустить `ansible-playbook site.yml`.
3. Плейбук выполняет `tasks/purge_revoked_operators.yml`:
   - удаляет `{{ operators_home }}/<name>/` на хосте;
   - удаляет `generated/mfa/<host>/<name>.mfa.txt`;
   - удаляет Unix-учётку и `/home/<name>` в контейнере;
   - перезапускает `mt_ssh_bastion` (handler `Restart ssh bastion container`).

**Dev shortcut:** `./scripts/test-repo-key.sh revoke <name> --apply`

### Ротация ключей и TOTP

- **SSH-ключ:** обновить поле `pubkey` оператора, перевыпустить плейбук.
- **TOTP:** удалить `.google_authenticator` оператора в `{{ bastion_home }}/operators/<name>/`, очистить или задать новый `mfa_secret`, перевыпустить плейбук. Новый секрет — из `generated/mfa/`.

### Действия при инциденте

При подозрительной активности (алерт `auditd`, SIEM):

```bash
sudo -u mt_bastion podman stop mt_ssh_bastion
```

Контейнер останавливается, активные сессии разрываются. Логи сессий на хостовой ОС сохраняются для расследования.

### Переключение на коммерческий PAM

Установить `is_commercial_pam: true`, задать `commercial_pam_api_url` и `commercial_pam_api_token` (Vault). Open-source компоненты не разворачиваются.

---

## 8. Audit-Safe речевые модули для встречи с CSO

Используйте формулировки ниже, чтобы продемонстрировать понимание ИБ-архитектуры и избежать overclaim.

| Избегать | Говорить |
| :--- | :--- |
| «Наш бастион на 100% гарантирует, что инженер ничего не сломает в вашей сети» | «Архитектура поддерживает принцип наименьших привилегий через прикладную микросегментацию. Инженер изолирован настройкой `PermitOpen` — доступ только к явно одобренным хостам и портам, без неконтролируемого форвардинга и сканирования подсетей» |
| «Решение полностью сертифицировано по КИИ и PCI-DSS» | «Технические контроли бастиона (локальный MFA, изоляция рантайма, append-only логирование) спроектированы в соответствии с требованиями PCI-DSS 4.0 и руководящих документов по защите КИИ, что упрощает прохождение регулярного ИБ-аудита вашей инфраструктуры» |
| «Логи абсолютно невозможно удалить» | «At-birth protection: каждый лог-файл получает `chattr +a` в момент создания; каталог `/var/log/bastion_sessions` принадлежит `mt_bastion` с правами `0750`. Рекомендуем стриминг `auditd` в SIEM» |
| «Jump-оператор не получит shell ни при каких условиях» | «Для роли jump в `authorized_keys` включён `restrict,port-forwarding` — PTY и shell заблокированы на уровне OpenSSH. Доступен только audited ProxyJump к whitelist-хостам» |

---

## 9. Checklist готовности инфраструктуры клиента

Используйте перед пресейлом и kick-off деплоя.

### Целевой хост бастиона

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

### Build-машина (фаза 1, вне Air Gap)

| # | Требование |
| :-: | :--- |
| 1 | Podman установлен |
| 2 | Доступ к базовому образу `alpine:3.19` (или предзагруженный mirror) |
| 3 | Выполнен `./trusted_download.sh`, получены `mt_bastion_image.tar` и `SHA256SUMS` |
| 4 | Артефакты переданы в контур клиента с сохранением контрольной суммы |

### Управляющая машина Ansible

| # | Требование |
| :-: | :--- |
| 1 | Ansible 2.14+ |
| 2 | Коллекции: `containers.podman`, `ansible.posix` |
| 3 | Заполнены `bastion_operators` и `bastion_permitted_targets` |
| 4 | Секреты (`mfa_secret`, `commercial_pam_api_token`) — в Ansible Vault |
| 5 | Каталог `generated/mfa/` защищён правами `0700`, не в git |

### Сеть и доступ

| # | Требование |
| :-: | :--- |
| 1 | Порт `bastion_ssh_port` (по умолчанию 2222) открыт только для доверенных источников |
| 2 | Список целей `PermitOpen` согласован с владельцами систем (формат `host:port`, без CIDR) |
| 3 | Маршрутизация с бастиона до целевых хостов проверена (`nc -zv target 22`) |
| 4 | SIEM-команда клиента уведомлена о правилах `auditd` (`mt_bastion_session_logs`, `mt_bastion_ssh_connect`) |
| 5 | При SIEM forward: `bastion_siem_server` доступен по TCP/RELP из DMZ |
| 6 | Compliance verify: `./scripts/bastion-compliance-verify.sh` exit 0 после деплоя |

### Dev / lab (инженеры MT Global)

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
| 3 | Выполнен тестовый вход: shell-оператор и jump-оператор |
| 4 | Проверено появление лог-файла в `/var/log/bastion_sessions/` (shell-сценарий) |
| 5 | Образ собран с `MFA_STRICT=1` (prod) |

---

## Приложение: структура репозитория

```
mt-bastion/
├── build/
│   ├── Containerfile
│   └── files/
│       ├── bastion-entrypoint.sh
│       └── bastion-shell-wrapper.sh
├── docs/
│   ├── README.md
│   ├── MT-Bastion-Whitepaper.md
│   ├── MT-Bastion-Troubleshooting-Workflow.md
│   ├── CSO-Demo-Runbook.md
│   └── Engineer-Onboarding.md
├── group_vars/
│   ├── all.yml                    # prod (CSO policy)
│   ├── all.yml.example
│   ├── local_lima.yml
│   └── dev/                       # lab: lab.yml, operators_merge.yml
├── inventory/
│   ├── hosts.yml                  # prod
│   └── local-lima.yml             # dev (Lima Rocky 9)
├── lab/keys/                      # gitignored lab SSH keys
├── scripts/
│   ├── dev-up.sh                  # one-shot dev stand
│   ├── bastion-compliance-verify.sh  # Tier 1 post-deploy checks
│   ├── test-repo-key.sh           # test access + bastion onboarding
│   └── repo-access.sh
├── openspec/                      # OpenSpec (SSH User CA QA, Tier 1 Free, …)
├── tasks/
│   ├── preflight_cso.yml
│   ├── prepare_os.yml
│   ├── verify_compliance_cso.yml  # tag: verify_compliance
│   ├── configure_rsyslog_siem.yml
│   ├── configure_source_firewall.yml
│   ├── archive_session_logs_worm.yml
│   ├── provision_operators.yml
│   ├── provision_operator_item.yml
│   ├── purge_revoked_operators.yml
│   ├── deploy_ssh_bastion.yml
│   ├── verify_image_cso.yml
│   └── commercial_pam.yml
├── .github/workflows/ci.yml       # syntax-check site.yml
├── templates/
│   ├── sshd_config.j2
│   ├── authorized_keys.j2
│   ├── auditd-bastion.rules.j2
│   └── google_authenticator.j2
├── tests/
│   ├── lima-rocky9.yaml
│   ├── start-lima.sh
│   ├── sync-artifacts.sh
│   └── README.md
├── generated/mfa/                 # gitignored TOTP output
├── site.yml
├── trusted_download.sh
└── requirements.yml
```

---

*Документ подготовлен MT Global. Технические детали актуальны для версии продукта 1.2.*
