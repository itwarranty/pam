## 1. Incident log naming (Phase A — v0.5.0)

- [x] 1.1 Update `build/files/pam-shell-wrapper.sh`: sanitized `incident_id` in log basename.
- [x] 1.2 Rebuild note in CSO Demo + Engineer Onboarding (`trusted_download.sh`).
- [x] 1.3 Lab test: operator with `incident_id` → log file matches `session_INC-*` pattern.
- [x] 1.4 Whitepaper Control Matrix row 21.

## 2. Shell command policy (Phase B — v0.5.1)

- [x] 2.1 Add `pam_shell_command_policy_enabled`, `pam_shell_command_denylist` to `group_vars/all.yml` + example.
- [x] 2.2 Create `build/files/pam-command-policy.sh` + integrate in shell wrapper (DEBUG trap or equivalent).
- [x] 2.3 Ansible: render `templates/command_denylist.j2` → host mount RO in container (`/etc/ssh-pam/command_denylist`).
- [x] 2.4 Extend `Containerfile` COPY for new scripts.
- [x] 2.5 CSO Demo block: attempt `rm -rf /` → denied + syslog.
- [x] 2.6 Troubleshooting §5.x + Whitepaper row 22.

## 3. Audit readonly role (Phase C — v0.5.2)

- [x] 3.1 Create `build/files/pam-audit-shell-wrapper.sh` (path guard + allowed commands).
- [x] 3.2 Update `templates/sshd_config.j2` for `access: audit`.
- [x] 3.3 Update `templates/authorized_keys.j2` macro for audit (no restrict).
- [x] 3.4 Preflight: validate `access` enum; block `audit` when `is_commercial_pam`.
- [x] 3.5 Lab operator in `group_vars/dev/audit_lab.yml`.
- [x] 3.6 CSO Demo block + Whitepaper row 23.

## 4. SSH brute-force protection (Phase D — v0.5.3)

- [x] 4.1 Create `tasks/configure_ssh_brute_force.yml` (firewalld rate limit path).
- [x] 4.2 Optional fail2ban: `templates/fail2ban-pam.conf.j2` + filter.
- [x] 4.3 Group vars: `pam_ssh_rate_limit_*`.
- [x] 4.4 Include task in `site.yml` when enabled.
- [x] 4.5 Extend `verify_compliance_cso.yml` + `pam-compliance-verify.sh`.
- [x] 4.6 Whitepaper row 24 + auditd rule doc if needed.

## 5. Break-glass (Phase E — v0.5.4)

- [x] 5.1 Group vars: `pam_break_glass_enabled`, `pam_break_glass_max_hours`.
- [x] 5.2 Extend `preflight_cso.yml` for break-glass rules.
- [x] 5.3 Extend `jit_filter_operators.yml` if needed (no change expected).
- [x] 5.4 Audit: `templates/auditd-pam.rules.j2` key `pam_break_glass_session`.
- [x] 5.5 Shell wrapper / syslog: `BREAK_GLASS=1` marker.
- [x] 5.6 Lab fixture `group_vars/dev/break_glass_lab.yml` + CSO Demo block.
- [x] 5.7 Troubleshooting break-glass runbook + Whitepaper row 25.

## 6. Documentation & archive

- [x] 6.1 Update `docs/README.md` Tier 2 roadmap link.
- [x] 6.2 Update `README.md` releases table (`v0.5.x`).
- [x] 6.3 Update `openspec/config.yaml` context when Tier 2 ships.
- [x] 6.4 After all phases: merge specs to `openspec/specs/`, archive change, git tag `v0.5.0` (or per-phase tags per CSO decision).
