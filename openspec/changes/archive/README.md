# Archived OpenSpec changes

Completed changes moved here after specs merged to `openspec/specs/`.

## Версии продукта (git tags)

| Tag | Коммит (примерно) | Содержание |
| :--- | :--- | :--- |
| **v0.1** | test-repo-key, baseline CSO | До Tier 1 |
| **v0.2.0** | Phase A only | compliance, tamper logs, source IP, SIEM, WORM |
| **v0.4.0** | Phase B + C + archive | JIT, User CA policy, specs merged |

> Отдельных тегов `v0.2.1` / `v0.3.0` нет: Phase B и C выпущены одним релизом **v0.4.0**.

## Архив changes

| Archive | Release | Notes |
| :--- | :--- | :--- |
| [2026-06-bastion-free-tier1-cso](./2026-06-bastion-free-tier1-cso/) | v0.2.0–v0.4.0 | Tier 1 Free Phases A–C — **все пункты tasks.md [x]** |
| [2026-06-ssh-user-ca-qa-mtglobal](./2026-06-ssh-user-ca-qa-mtglobal/) | v0.4.0 (templates) | Live PKI QA — **§3–5, 6.2 ещё [ ]** (нужен org CA) |

## Статус «всё реализовано?»

| Область | В репо | Вне репо |
| :--- | :---: | :---: |
| Tier 1 код + Ansible + доки | ✅ | — |
| Opt-in: JIT timer, SIEM, WORM | ✅ (выкл. по умолчанию) | клиент включает в group_vars |
| SSH User CA **policy** + signing example | ✅ | — |
| SSH User CA **live QA** на Rocky 9 | templates only | CA pubkey, deploy, acceptance |
| Prod GA certificates | preflight + SOP | `bastion_ssh_user_ca_qa_complete: true` после sign-off |

Active specifications: `openspec/specs/*/spec.md`
