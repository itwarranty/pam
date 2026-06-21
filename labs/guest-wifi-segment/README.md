# Guest Wi‑Fi segment lab (open source, low resource)

Лёгкая эмуляция **гостевой Wi‑Fi** + **corp internal** + **DMZ (bastion)** на **одном Linux-сервере** с Podman.

Ресурсы: ~4 Alpine-контейнера, **~150–400 MiB RAM**, без VM/KVM.

---

## Профиль вашей сети (изнутри, 2026-06-17)

| Параметр | Значение |
|----------|----------|
| Клиент | `10.1.13.51/24` (Wi‑Fi `en0`) |
| Шлюз | `10.1.13.1` |
| DNS | `193.201.228.32`, `195.16.119.5` |
| Публичный egress (NAT) | `185.6.175.156` |
| Captive portal | нет (`204` от connectivity check) |
| Изоляция | `10.0.0.1` и др. RFC1918 с guest **не пингуются** |
| Wi‑Fi security | WPA2/WPA3 Personal |

### Снаружи (как видит шлюз / заказчик)

Guest Wi‑Fi почти всегда выходит в интернет **одним NAT-IP** (у вас `185.6.175.156`).  
Private `10.1.13.0/24` снаружи **не маршрутизируется**.

Для SSH PAM на prod это значит:

- `allowed_sources` для инженера с guest Wi‑Fi → **публичный egress IP** (или CIDR провайдера), **не** `10.1.13.0/24`.
- Прямой доступ guest → internal target (`10.0.1.10`) должен быть **заблокирован** сетью; только через bastion/gateway.

---

## Топология lab

```
                    ┌─────────────────────────────────────┐
  guest_wifi        │  lab-router (iptables)              │
  10.1.13.0/24      │  • guest → corp: DROP             │
       │            │  • guest → dmz:2222: ACCEPT       │
  ┌────┴────┐       │  • dmz → corp: ACCEPT             │
  │ guest-pc│       └───────┬─────────────┬─────────────┘
  │ .51     │               │             │
  └─────────┘          dmz │        corp │
                    10.0.2.0/24   10.0.1.0/24
                    bastion-mock   target (ssh)
                    :2222          10.0.1.10
```

Сегмент `10.0.1.0/24` совпадает с lab-адресами в `group_vars/dev/lab.yml` (`10.0.1.10`).

---

## Требования

- Linux x86_64 (Rocky 9, Fedora, Ubuntu — подойдёт)
- Podman (`dnf install podman`)
- Rootful Podman рекомендуется (iptables в router); rootless — см. ограничения ниже

---

## Быстрый старт

```bash
cd itwarranty-pam/labs/guest-wifi-segment
chmod +x scripts/*.sh router/entrypoint.sh

./scripts/up.sh
./scripts/verify.sh

# «Ноутбук в guest Wi‑Fi»
podman exec -it bastion-guest-lab-guest-pc sh
# внутри: ping 10.1.13.1; ping 10.0.1.10 (fail); nc -zv 10.0.2.10 2222 (ok)

./scripts/down.sh
```

С хоста bastion-mock: `ssh -p 12222 bastion-mock@127.0.0.1` (password `lab`).

---

## Интеграция с SSH PAM

1. Поднимите lab: `./scripts/up.sh`
2. Деплой шлюза как обычно (`site.yml` / `dev-up` на том же сервере)
3. Подключите контейнер к DMZ lab:

```bash
./scripts/attach-bastion.sh
```

4. На guest-pc проверьте SSH к реальному шлюзу (ключ + TOTP lab).
5. Для эмуляции **prod policy** задайте у оператора:

```yaml
allowed_sources:
  - "185.6.175.156/32"   # ваш guest egress; в lab можно 10.1.13.0/24 если bastion в DMZ L2
```

---

## Настройка под другую guest-сеть

Отредактируйте `topology.env` (CIDR, gateway, egress IP).

---

## Альternatives (если понадобится больше)

| Инструмент | Когда |
|------------|--------|
| [Containerlab](https://containerlab.dev/) | YAML-топология, CI, больше нод |
| [netlab](https://netlab.tools/) | netlab → containerlab/libvirt |
| Vagrant + libvirt | Полноценные Rocky VM (тяжелее) |

Этот lab намеренно минимален: только Podman + iptables.

---

## Ограничения

- Это **L3-модель**, не эмуляция Wi‑Fi (802.11, WPA, captive portal).
- Mock bastion/target — Alpine+sshd; для Tier 3/4 тестов подключайте `ssh_bastion`.
- Rootless Podman: `--ip` и iptables в router могут не работать — используйте `sudo podman`.
- На Lima с Mac mount репо может быть **read-only** — `up.sh` копирует router script в `/tmp` (SELinux `:Z` на mount не нужен).
