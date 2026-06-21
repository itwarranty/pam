## 1. Compliance verify (Phase A — no dependencies)

- [x] 1.1 Create `tasks/verify_compliance_cso.yml` with checks from design D6.
- [x] 1.2 Create `scripts/bastion-compliance-verify.sh` (host-local, mirrors Ansible checks).
- [x] 1.3 Add `site.yml` task include with tag `verify_compliance` (runs after deploy, optional).
- [x] 1.4 Add CSO Demo Runbook block «Compliance verify».
- [x] 1.5 Add Whitepaper Control Matrix row.

## 2. Tamper-evident session logs (Phase A)

- [x] 2.1 Extend `build/files/bastion-shell-wrapper.sh`: trap on EXIT writes `*.sha256` sidecar.
- [x] 2.2 Support optional env `BASTION_INCIDENT_ID` (from operator `incident_id` via sshd `SetEnv` Match block — if feasible).
- [x] 2.3 Document verification in Troubleshooting Workflow §5.3.
- [x] 2.4 Optional: `tasks/archive_session_logs_worm.yml` when `bastion_worm_archive_dir` set.
- [x] 2.5 Rebuild image via `trusted_download.sh`; update CSO demo ls + sha256 check.

## 3. Source IP restriction (Phase A)

- [x] 3.1 Extend `bastion_operators` schema: `allowed_sources: []` in `all.yml.example`.
- [x] 3.2 Update `templates/authorized_keys.j2` with `from="..."` when list non-empty.
- [x] 3.3 Optional firewalld rich rules task when `bastion_allowed_source_cidrs` set globally.
- [x] 3.4 Preflight assert when `bastion_require_source_ip: true`.
- [x] 3.5 CSO demo: connect from wrong IP → fail.

## 4. SIEM syslog export (Phase A)

- [x] 4.1 Create `templates/rsyslog-bastion-siem.conf.j2`.
- [x] 4.2 Create `tasks/configure_rsyslog_siem.yml` (install rsyslog if needed, drop-in, restart).
- [x] 4.3 Document CEF/field mapping appendix in spec `bastion-siem-syslog-export`.
- [x] 4.4 Whitepaper: client SIEM responsibility disclaimer unchanged; add forwarder setup steps.

## 5. JIT access windows (Phase B)

- [x] 5.1 Schema: `valid_from`, `valid_until`, `incident_id` on operators.
- [x] 5.2 Ansible filter task: compute expired operators before provision; merge with purge.
- [x] 5.3 Extend `purge_revoked_operators.yml` OR new `tasks/jit_expire_operators.yml`.
- [x] 5.4 systemd timer + service template for periodic `ansible-playbook site.yml --tags jit_purge` (document client must install timer).
- [x] 5.5 Update Troubleshooting Workflow §5.2 with automatic expiry path.
- [x] 5.6 Lab test: operator with `valid_until` in past → removed on playbook run.

## 6. SSH User CA prod Free (Phase C — depends on ssh-user-ca-qa)

- [x] 6.1 Complete QA tasks in `ssh-user-ca-qa` (PKI access required).
- [x] 6.2 Add preflight warning when prod uses raw `pubkey` without CSO waiver flag.
- [x] 6.3 Add `bastion_allow_raw_pubkey_prod: false` default in `group_vars/all.yml`.
- [x] 6.4 Document cert renewal SOP in Whitepaper §7.
- [x] 6.5 Optional: `scripts/sign-operator-cert.sh.example` (offline signing helper, no private key in repo).

## 7. Documentation & archive

- [x] 7.1 Update `docs/README.md` with Tier 1 roadmap link.
- [x] 7.2 Update Whitepaper Policy Gate table (items 14–18).
- [x] 7.3 After all phases: merge specs to `openspec/specs/` and archive change.
