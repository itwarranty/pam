# Archived OpenSpec changes

Completed changes moved here after specs merged to `openspec/specs/`.

## Версии продукта (git tags)

| Tag | Коммит (примерно) | Содержание |
| :--- | :--- | :--- |
| **v0.1** | test-repo-key, baseline CSO | До Tier 1 |
| **v0.2.0** | Phase A only | compliance, tamper logs, source IP, SIEM, WORM |
| **v0.4.0** | Phase B + C + archive | JIT, User CA policy, specs merged |
| **v0.5.0** | Tier 2 + archive | incident naming, denylist, audit, rate limit, break-glass |
| **v0.6.0** | Tier 3 + archive | SSH gateway, target recording, session-ctl |
| **v1.0.0** | Tier 4 + archive | SSH PAM GA: search, policy v2, watch, Vault, HA |
| **v1.1.0** | Tier 5 + archive | FIDO-Anchor MFA: sk keys + TOTP modes |

## Архив changes

| Archive | Release | Notes |
| :--- | :--- | :--- |
| [2026-06-pam-free-tier1-cso](./2026-06-pam-free-tier1-cso/) | v0.2.0–v0.4.0 | Tier 1 Free Phases A–C — **все пункты tasks.md [x]** |
| [2026-06-pam-free-tier2-cso](./2026-06-pam-free-tier2-cso/) | v0.5.0 | Tier 2 Free Phases A–E — **все пункты tasks.md [x]** |
| [2026-06-pam-ssh-gateway-tier3](./2026-06-pam-ssh-gateway-tier3/) | v0.6.0 | Tier 3 SSH Gateway — **все пункты tasks.md [x]** |
| [2026-06-pam-free-tier4-ssh-pam-complete](./2026-06-pam-free-tier4-ssh-pam-complete/) | v1.0.0 | Tier 4 SSH PAM GA — **§10 org gate [ ]** |
| [2026-06-pam-fido-anchor-mfa](./2026-06-pam-fido-anchor-mfa/) | v1.1.0 | Tier 5 FIDO — **§9 acceptance [ ]** |
| [2026-06-ssh-user-ca-qa](./2026-06-ssh-user-ca-qa/) | v0.4.0 (templates) | Live PKI QA — **§3–5, 6.2 ещё [ ]** (нужен org CA) |

## Статус «всё реализовано?»

| Область | В репо | Вне репо |
| :--- | :---: | :---: |
| Tier 1 код + Ansible + доки | ✅ | — |
| Tier 2 код + Ansible + доки | ✅ | — |
| Tier 3 gateway + session-ctl | ✅ | — |
| Tier 4 search, policy v2, watch, Vault, HA | ✅ | — |
| Tier 5 FIDO-Anchor MFA (sk + TOTP modes) | ✅ | FIDO hardware for §9 acceptance |
| Opt-in: JIT timer, SIEM, WORM | ✅ (выкл. по умолчанию) | клиент включает в group_vars |
| SSH User CA **policy** + signing example | ✅ | — |
| SSH User CA **live QA** на Rocky 9 | templates only | CA pubkey, deploy, acceptance |
| Prod GA certificates | preflight + SOP | `pam_ssh_user_ca_qa_complete: true` после sign-off |

Active specifications: `openspec/specs/*/spec.md`
