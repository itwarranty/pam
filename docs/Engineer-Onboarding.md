# Onboarding инженера MT: Bastion

Репозиторий **private**: `git@github.com:MT-Global-Team/mt-bastion.git`

---

## Часть A. Для администратора (выдача доступа)

### Рекомендуемый способ — team `bastion-engineers`

Team уже создан и имеет **Write** к этому репозиторию:

https://github.com/orgs/MT-Global-Team/teams/bastion-engineers

**Добавить инженера:**

1. Откройте ссылку выше → **Members** → **Add member**
2. Выберите GitHub username сотрудника MT Global  
   *(сначала пригласите в org: https://github.com/orgs/MT-Global-Team/people → Invite member)*

Инженер после этого: `git clone git@github.com:MT-Global-Team/mt-bastion.git`

### Альтернатива — прямой collaborator

1. Откройте https://github.com/MT-Global-Team/mt-bastion  
2. **Settings** → **Collaborators and teams** (или **Manage access**)  
3. **Add people** / **Invite teams**  
4. Укажите GitHub username или email инженера  
5. Роль:
   - **Read** — только тестирование (clone, pull)
   - **Write** — тестирование + push в ветки / PR

Инженер получит email-приглашение и должен принять его.

### Вариант 2 — через GitHub CLI

```bash
# Read — тестирование
gh api repos/MT-Global-Team/mt-bastion/collaborators/USERNAME \
  -X PUT -f permission=pull

# Write — разработка
gh api repos/MT-Global-Team/mt-bastion/collaborators/USERNAME \
  -X PUT -f permission=push
```

Замените `USERNAME` на логин GitHub инженера.

### Вариант 3 — членство в org MT-Global-Team

Если инженер — штатный сотрудник:

1. https://github.com/orgs/MT-Global-Team/people → **Invite member**  
2. После принятия — добавьте его в team с доступом к `mt-bastion`  
   (или выдайте доступ к repo по варианту 1)

### Что не передавать инженерам

- Prod-секреты (`group_vars/all.yml` операторы, Ansible Vault)
- Private SSH User CA
- Private keys `lab/keys/*.lab` — генерируются локально скриптом `dev-up.sh`

---

## Часть B. Для инженера (первый запуск)

### 1. SSH-ключ GitHub

```bash
ssh-keygen -t ed25519 -C "you@mtglobal.team"
cat ~/.ssh/id_ed25519.pub
```

Добавьте ключ: https://github.com/settings/ssh-keys

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

Скрипт: lab-ключи, сборка образа, Lima VM, Ansible deploy.  
Операторы и TOTP — из `group_vars/dev.yml` (Vault не нужен).

### 5. Проверка SSH к бастion-контейнеру

```bash
ssh -p 2222 -i lab/keys/engineer-jump.lab engineer-jump@127.0.0.1
ssh -p 2222 -i lab/keys/engineer-shell.lab engineer-shell@127.0.0.1
```

TOTP: otpauth URI в комментариях `group_vars/dev.yml`.

### 6. Сценарии для отчёта

Прогоните чеклист: [CSO-Demo-Runbook.md](CSO-Demo-Runbook.md)

---

## Часть C. Работа с кодом

| Действие | Команда |
|:---|:---|
| Обновить repo | `git pull` |
| Новая фича | `git checkout -b feature/...` → PR в `main` |
| Синтаксис playbook | `ansible-playbook --syntax-check -i inventory/local-lima.yml site.yml` |

Prod-деплой (`inventory/hosts.yml` + Vault) — только по согласованию с lead / CSO.

---

## Troubleshooting

См. [MT-Bastion-Troubleshooting-Workflow.md](MT-Bastion-Troubleshooting-Workflow.md)
