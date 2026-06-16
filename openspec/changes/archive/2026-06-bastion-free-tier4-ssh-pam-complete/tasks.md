## 1. Session search (Phase A — v0.7.0)

- [x] 1.1 Create `scripts/bastion-session-search.sh` (JSONL filter, table + `--json`).
- [x] 1.2 Optional `--grep` over `.log` files with date window.
- [x] 1.3 Vars: `bastion_session_search_enabled`; document `jq` package on Rocky 9.
- [x] 1.4 Install path: `/usr/local/bin/bastion-session-search` via Ansible task (optional tag `session_search`).
- [x] 1.5 Troubleshooting: search examples; CSO Demo block.
- [x] 1.6 Whitepaper Control Matrix row 29.

## 2. Command policy v2 (Phase B — v0.7.1)

- [x] 2.1 Add `python3` to `build/Containerfile` (minimal) OR pure-shell inspector — document choice in design.
- [x] 2.2 Create `build/files/bastion-pty-inspector.py` + `bastion-pty-inspector.sh` wrapper.
- [x] 2.3 Integrate in `bastion-ssh-gateway-exec.sh` when `bastion_gateway_command_policy_v2_enabled`.
- [x] 2.4 Integrate in `bastion-shell-wrapper.sh` when `bastion_shell_command_policy_v2_enabled`.
- [x] 2.5 Vars: `bastion_gateway_deny_kill_session` in `group_vars/all.yml`.
- [x] 2.6 CSO Demo: deny `rm -rf /` on target without remote rc; Whitepaper v2 section.
- [x] 2.7 Keep v1 remote rc fallback when v2 disabled.

## 3. Live session moderation (Phase C — v0.7.2)

- [x] 3.1 Create `scripts/bastion-session-watch.sh` (tail -f registry log_path).
- [x] 3.2 JSONL `moderator_watch_start` events.
- [x] 3.3 Sudo/group doc: `mt_bastion_moderators` or audit SSH user.
- [x] 3.4 CSO Demo four-eyes block; Troubleshooting §5.7.
- [x] 3.5 Whitepaper row 30.

## 4. HashiCorp Vault (Phase D — v0.7.3)

- [x] 4.1 Extend `bastion_targets` schema: `vault_secret_path`, `vault_secret_key`.
- [x] 4.2 Create `tasks/fetch_vault_target_keys.yml`; extend `provision_bastion_targets.yml`.
- [x] 4.3 Add `community.hashi_vault` to `requirements.yml` (conditional doc).
- [x] 4.4 Preflight: mutual exclusion vault_path vs identity_file.
- [x] 4.5 Vars: `bastion_vault_*` in `all.yml.example`.
- [x] 4.6 Lab fixture with mock Vault or skip document for internal prod only.

## 5. OIDC/SAML SSH user certs (Phase E — v0.7.4)

- [x] 5.1 Create `scripts/sign-operator-cert-oidc.sh.example`.
- [x] 5.2 Create `scripts/oidc-offline-token.sh.example`.
- [x] 5.3 Create `scripts/sign-operator-cert-saml.sh.example` (saml2aws bridge stub).
- [x] 5.4 Vars: `bastion_oidc_*`, `bastion_oidc_cert_policy_enabled` in example.
- [x] 5.5 Preflight when OIDC policy enabled: certificate required.
- [x] 5.6 Whitepaper §OIDC; link to existing User CA trust specs.
- [ ] 5.7 Complete internal PKI QA tasks (ssh-user-ca-qa-mtglobal §3–5) on MT Global CA.

## 6. HA active-passive (Phase F — v0.7.5)

- [x] 6.1 Create `docs/MT-Bastion-HA-Runbook.md`.
- [x] 6.2 Create `group_vars/ha.yml.example`, inventory `ha-cluster.yml.example`.
- [x] 6.3 Create `scripts/bastion-ha-promote.sh`.
- [x] 6.4 Ansible: shared mount task for `audit_log_dir` when `bastion_ha_enabled`.
- [x] 6.5 Document limitations (registry, session loss).

## 7. v1.0 GA release (Phase G)

- [x] 7.1 Rename `MT-Bastion-Client-Without-PAM.md` → `MT-Dostup-SSH-PAM-Overview.md`; update all links.
- [x] 7.2 Create `docs/MT-Bastion-Battlecard-SKDPU-SSH.md`.
- [x] 7.3 Create `docs/MT-Bastion-SoW-SSH-Access.md`.
- [x] 7.4 Create `group_vars/prod.yml.example`.
- [x] 7.5 Create `CHANGELOG.md` (v0.1 → v1.0.0).
- [x] 7.6 Extend `bastion-compliance-verify.sh` (gateway manifest, jq optional).
- [x] 7.7 Update README releases table; Whitepaper version 1.6 + Policy Gate #29–31.
- [x] 7.8 Internal prod acceptance checklist (tasks §10).
- [x] 7.9 Merge specs to `openspec/specs/`; archive change; tag `v1.0.0`.

## 8. Documentation index

- [x] 8.1 Update `docs/README.md` — PAM positioning, Tier 4 links.
- [x] 8.2 Update `openspec/config.yaml` — Tier 4 active → complete after archive.

## 9. Agent prompt

- [x] 9.1 Add R&D prompt block to `tasks.md` footer or `docs/Engineer-Onboarding.md` §Tier 4.

## 10. Internal prod acceptance (release gate)

- [ ] 10.1 Gateway session recorded; search finds it by operator + date.
- [ ] 10.2 Policy v2 denies destructive command on target.
- [ ] 10.3 Moderator watch on live session (audit user).
- [ ] 10.4 Session kill + JIT purge still work.
- [ ] 10.5 Compliance verify exit 0 on internal prod.
- [ ] 10.6 OIDC-signed cert login (or internal CA cert) for one operator.
- [ ] 10.7 HA runbook drill documented (tabletop or lab).

---

## R&D agent prompt (copy to Cursor)

```
Implement MT: Bastion Tier 4 — complete SSH PAM in Free (target v1.0.0).

OpenSpec: openspec/changes/archive/2026-06-bastion-free-tier4-ssh-pam-complete/
Read: proposal.md, design.md, tasks.md, all specs/*.

Depends on Tier 3 (v0.6.0 gateway). Do not add RDP/web. All features stay SSH PAM in Free.

Order: Phase A → B → C → D → E → F → G. Mark tasks.md [x] as done.

Phase A: scripts/bastion-session-search.sh
Phase B: bastion-pty-inspector + gateway/shell integration, v1 fallback
Phase C: bastion-session-watch.sh + JSONL moderator events
Phase D: fetch_vault_target_keys.yml + community.hashi_vault
Phase E: OIDC signing example scripts + preflight; complete internal PKI QA
Phase F: HA runbook + ha.yml.example + bastion-ha-promote.sh
Phase G: PAM docs rename, battlecard, SoW, CHANGELOG, v1.0.0 tag prep

Validate each phase: ansible-playbook --syntax-check; lab gateway_lab.yml where applicable.
Rebuild image after Containerfile changes (trusted_download.sh).
```
