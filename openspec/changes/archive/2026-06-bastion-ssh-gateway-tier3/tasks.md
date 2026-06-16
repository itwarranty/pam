## 1. Target inventory & provisioning (Phase A — v0.6.0)

- [x] 1.1 Schema `bastion_targets[]` in `group_vars/all.yml` + `all.yml.example` (id, host, port, account, identity_file, host_key_fingerprint, tags).
- [x] 1.2 Create `tasks/provision_bastion_targets.yml` (keys, known_hosts, SELinux, permissions).
- [x] 1.3 Preflight: gateway `permit_open` resolves to targets; vault/plaintext key policy.
- [x] 1.4 Include provision task in `site.yml` before `provision_operators.yml`.

## 2. Gateway wrappers & container (Phase A)

- [x] 2.1 Create `build/files/bastion-ssh-gateway-wrapper.sh` (menu, session register, env).
- [x] 2.2 Create `build/files/bastion-ssh-gateway.sh` (ssh client, script record, sidecars).
- [x] 2.3 Extend `build/Containerfile`: openssh-client, COPY wrappers, chmod.
- [x] 2.4 Mount `targets/` and `runtime/sessions/` in `deploy_ssh_bastion.yml`.
- [x] 2.5 Update `templates/sshd_config.j2` for `access: gateway`.
- [x] 2.6 Update `templates/authorized_keys.j2` (no restrict for gateway).
- [x] 2.7 Extend preflight: `access` enum includes `gateway`.

## 3. Target session recording (Phase A)

- [x] 3.1 Log naming `gateway_*` with incident + target id (reuse sanitize helpers).
- [x] 3.2 `.meta` fields: MODE, TARGET, TARGET_HOST, TARGET_ACCOUNT.
- [x] 3.3 Rebuild docs: `trusted_download.sh` in Engineer Onboarding + CSO Demo.
- [x] 3.4 Lab: `group_vars/dev/gateway_lab.yml` + mock target (document Lima setup).

## 4. Session control plane (Phase B — v0.6.1)

- [x] 4.1 Session registry JSON in `{{ bastion_home }}/runtime/sessions/`.
- [x] 4.2 Create `scripts/bastion-session-ctl.sh` (list/kill; host wrapper with podman exec).
- [x] 4.3 Integrate JIT purge: kill sessions for revoked operators (`tasks/jit_purge.yml` or handler).
- [x] 4.4 Ansible tag `session_kill` + extra vars.
- [x] 4.5 CSO Demo block: list + kill live session.
- [x] 4.6 Troubleshooting §5.6 session kill runbook.

## 5. Gateway command policy (Phase C — v0.6.2)

- [x] 5.1 Apply denylist to gateway PTY (extend `bastion-command-policy-rc.sh` or gateway-local tap).
- [x] 5.2 CSO Demo: denied command on target session.
- [x] 5.3 Whitepaper limitation disclaimer (shared with shell policy).

## 6. Known hosts & prod hardening (Phase C)

- [x] 6.1 Template `templates/ssh_known_hosts_targets.j2` → mount in container.
- [x] 6.2 `bastion_gateway_lab_mode` for lab-only `accept-new`.
- [x] 6.3 auditd rule optional: read target identity files (`mt_bastion_target_key_read`).

## 7. Structured export (Phase D — v0.6.3)

- [x] 7.1 Append JSONL in gateway wrapper start/end.
- [x] 7.2 Document SIEM `imfile` appendix in spec + Whitepaper.
- [x] 7.3 Troubleshooting: `jq` examples for auditors.

## 8. Jump vs gateway policy (Phase E — v0.6.4)

- [x] 8.1 Vars: `bastion_prod_require_gateway`, `bastion_prod_target_tags`, `bastion_jump_risk_acceptance_required`.
- [x] 8.2 Operator field `bastion_jump_approved: true` waiver.
- [x] 8.3 Preflight rules per `bastion-jump-gateway-access-policy` spec.
- [x] 8.4 Whitepaper §4 scenario C (gateway) + Policy Gate #26–28.
- [x] 8.5 Client 1-pager: `docs/MT-Bastion-Client-Without-PAM.md` (Russian, adoption checklist).

## 9. Documentation & archive

- [x] 9.1 Update `docs/README.md`, root `README.md` releases (`v0.6.x`).
- [x] 9.2 Update `openspec/config.yaml` Tier 3 active change.
- [x] 9.3 CSO Demo Runbook gateway blocks (connect, log verify, kill, jump vs gateway narrative).
- [x] 9.4 Extend `bastion-compliance-verify.sh` for gateway lab smoke (optional).
- [x] 9.5 After all phases: merge specs to `openspec/specs/`, archive change, tag `v0.6.0`.

## 10. Market adoption checklist (release gate)

- [x] 10.1 Document answers to auditor five questions (who/when/where/what/revoke) with gateway enabled.
- [x] 10.2 SoW snippet: «SSH к согласованному перечню; режим gateway для интерактива».
- [x] 10.3 Confirm segment fit note (200–1000, no PAM, Linux) in client 1-pager.
