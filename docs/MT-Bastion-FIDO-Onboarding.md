# MT: Bastion — FIDO-Anchor MFA (Tier 5)

Онбординг оператора и CSO для **FIDO2 / platform SSH key** + **offline TOTP** на бастion.

## Модель (dual-anchor)

| # | Фактор | Где |
|:-:|:---|:---|
| 1 | FIDO2 / Touch ID / YubiKey (`ed25519-sk -O verify-required`) | ноутбук оператора |
| 2 | TOTP (`pam_google_authenticator`) | контейнер бастion |
| 3 (opt.) | SSH user cert, окно JIT (`valid_until`) | offline CA |

**Не реализуется:** WebAuthn в PAM, `mt-ssh`/`tsh`, IdP на бастion (Tier 4 OIDC — отдельный opt-in).

## 1. Генерация ключа (оператор)

```bash
ssh-keygen -t ed25519-sk -O verify-required \
  -C "engineer1@mtglobal.team" \
  -f ~/.ssh/mt-bastion-fido
```

- **macOS:** Touch ID / Secure Enclave при каждом `ssh`.
- **Linux/Windows:** YubiKey или platform sk; OpenSSH **≥ 8.4** для `ed25519-sk`.
- Без `-O verify-required` ключ слабее — CSO требует verify.

Опционально ECDSA-sk: только если CSO включил `bastion_fido_ecdsa_sk_allowed: true`.

## 2. Регистрация в Ansible

```yaml
bastion_operators:
  - name: engineer1
    access: gateway
    pubkey: "{{ lookup('file', playbook_dir + '/vault/keys/engineer1-fido.pub') }}"
    mfa_secret: "{{ vault_mfa_engineer1 }}"  # или generated/mfa/
    valid_from: "2026-06-01T08:00:00+00:00"
    valid_until: "2026-06-01T20:00:00+00:00"
```

Prod profile (`group_vars/prod.yml.example`):

```yaml
bastion_require_fido_pubkey: true
bastion_mfa_mode: fido_totp
```

## 3. JIT + сертификат (opt.)

```bash
export MT_BASTION_USER_CA_KEY=/secure/mtglobal.team-user-ca
export OPERATOR_NAME=engineer1
export SK_PUBKEY_PATH=~/.ssh/mt-bastion-fido.pub
export VALID_UNTIL=2026-06-01T20:00:00Z
./scripts/sign-operator-cert-jit.sh.example
```

Срок cert ≤ `bastion_cert_max_validity_hours` (72h по умолчанию) или явное JIT-окно.

## 4. Режимы MFA

| `bastion_mfa_mode` | Поведение |
|:---|:---|
| `totp` | v1.0: любой pubkey/cert + TOTP |
| `fido_totp` | **Prod:** FIDO-sk + TOTP (рекомендуется) |
| `fido_only` | Только FIDO-sk, **без TOTP** — только с `bastion_fido_only_waiver: true` + CSO review |

## 5. Pilot rollout (CSO)

1. **Lab:** `bastion_require_fido_pubkey: false` — legacy `.lab` keys работают.
2. **Pilot:** 1–2 оператора с sk + `bastion_mfa_mode: fido_totp`, остальные в `bastion_fido_waiver_operators`.
3. **Prod:** `bastion_require_fido_pubkey: true`, waivers пусты.
4. **Verify:** `bastion-compliance-verify.sh` с `BASTION_REQUIRE_FIDO_PUBKEY=1`.

## 6. Lab с FIDO (optional)

```bash
BASTION_FIDO_LAB=1 ./scripts/dev-up.sh
ssh -p 2222 -i lab/keys/engineer-fido.lab engineer-fido@127.0.0.1
# TOTP: FIDOLABFIDOLABFIDOLABFIDOLABFIDO (fido_lab.yml)
```

Без FIDO hardware — sk key не создаётся; lab regression на `.lab` keys без изменений.

## 7. Waivers (migration)

```yaml
bastion_fido_waiver_operators:
  - legacy-contractor-01
```

Preflight пропускает listed operators при strict FIDO. Удалить после миграции.

## 8. Audit-safe формулировки

| Избегать | Говорить |
|:---|:---|
| «FIDO на сервере бастion» | «FIDO привязан к ключу на рабочей станции; бастion проверяет sk-pubkey + TOTP» |
| «Как Teleport tsh» | «Стандартный OpenSSH + Security-as-a-Code, без vendor client» |
| «Биометрия хранится на бастion» | «Touch ID/PIN только на устройстве оператора (client-side verification)» |

## 9. vs Teleport / СКДПУ

- **Teleport:** FIDO через proprietary client.
- **MT «МТ Доступ»:** `ssh` + `ed25519-sk` + Git/Ansible policy — см. [Battlecard](./MT-Bastion-Battlecard-SKDPU-SSH.md).

---

*MT Global — FIDO Onboarding v1.1*
