## Why

SSH PAM **Tier 1** (`v0.4.0`) delivers CSO-grade SSH jump controls: JIT windows, tamper-evident logs, SIEM forward, source IP, compliance verify, and SSH User CA prod policy. Enterprise buyers still ask for **emergency access**, **command safety on shell role**, **brute-force hardening**, **ITSM-correlated log filenames**, and **read-only auditor accounts** — without a paid portal or multi-protocol PAM.

Tier 2 closes these objections **within SSH-only Free scope**: declarative Ansible, Air Gap compatible, Rocky Linux 9 only.

## What Changes

### 1. Break-glass emergency access

- Optional `break_glass: true` on operator with mandatory short `valid_until` and `incident_id`.
- Global gate `pam_break_glass_enabled: false` (prod opt-in).
- Enhanced audit tags (auditd key, syslog, session log prefix).
- Reuses JIT purge for auto-revoke after window.

### 2. Shell command policy (denylist)

- Configurable `pam_shell_command_denylist` (default dangerous patterns).
- Enforced in `pam-shell-wrapper.sh` for `access: shell` only.
- Blocked commands logged to auditd/syslog; session continues.

### 3. SSH brute-force / rate protection

- Host-level protection for `pam_ssh_port` (firewalld rate limit and/or fail2ban).
- Document interaction with MFA and source IP restrictions.
- Extend `verify_compliance` when enabled.

### 4. Incident ID in session log filename

- When `incident_id` is set, log basename includes sanitized ticket ref: `session_INC-2026-8942_user_…`.
- `.meta` / `.sha256` sidecars unchanged; backward compatible when `incident_id` absent.

### 5. Read-only audit role (`access: audit`)

- New operator role: view session logs under `/var/log/pam_sessions` only.
- No ProxyJump, no shell on targets, no write to log directory.
- ForceCommand → `pam-audit-shell-wrapper.sh`.

## Capabilities

### New Capabilities

| Capability | Spec |
|:---|:---|
| Break-glass emergency access | `specs/pam-break-glass-access/spec.md` |
| Shell command denylist | `specs/pam-shell-command-policy/spec.md` |
| SSH brute-force protection | `specs/pam-ssh-brute-force-protection/spec.md` |
| Incident-correlated log naming | `specs/pam-incident-log-naming/spec.md` |
| Read-only audit role | `specs/pam-audit-readonly-role/spec.md` |

### Modified Capabilities

- `gateway-jit-access-windows` — break-glass operators MUST use `valid_until`; purge semantics unchanged.
- `gateway-tamper-evident-session-logs` — filename pattern when `incident_id` present.
- `pam-compliance-verify` — optional checks for fail2ban/firewalld rate limit and break-glass gate.

## Impact

- **Tasks:** `tasks/configure_ssh_brute_force.yml`, extend `preflight_cso.yml`, `provision_operator_item.yml`
- **Build:** `build/files/pam-shell-wrapper.sh`, new `pam-audit-shell-wrapper.sh`, optional `pam-command-policy.sh`
- **Templates:** `sshd_config.j2`, `authorized_keys.j2`, fail2ban jail template
- **Group vars:** `pam_break_glass_*`, `pam_shell_command_denylist`, `pam_ssh_rate_limit_*`
- **Docs:** Whitepaper Control Matrix rows 21–25, CSO Demo blocks, Troubleshooting §5.x

## Non-Goals (remain Paid / SSH PAM)

- ITSM approval workflow UI, OIDC/SAML, credential vault
- Full session command indexing / video replay
- RDP/web/K8s gateways, HA cluster, central control plane
- Automated break-glass approval via external API (declarative YAML only)

## Dependencies

- **Requires:** Tier 1 GA specs in `openspec/specs/` (JIT purge, tamper logs, compliance verify).
- **Independent phases:** incident log naming and command policy can ship before break-glass.

## Success Criteria (CSO)

- [ ] Break-glass operator cannot be provisioned without `incident_id`, `valid_until`, and CSO gate flag.
- [ ] Denied shell commands (`rm -rf /`, `iptables -F`) blocked and logged.
- [ ] Repeated failed SSH auth from same IP triggers temporary block (when rate limit enabled).
- [ ] Session log filename contains ITSM ticket id when configured.
- [ ] `access: audit` operator can read logs but cannot ProxyJump or modify logs.
- [ ] `pam-compliance-verify.sh` passes on lab deploy with Tier 2 features enabled.
