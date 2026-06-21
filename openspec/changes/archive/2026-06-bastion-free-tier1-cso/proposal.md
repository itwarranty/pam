## Why

SSH PAM (open-source tier of **SSH PAM**) already delivers SSH jump-host controls with CSO Policy Gate, MFA strict, declarative revoke, and session logging. Competing products (Teleport, Boundary, enterprise PAM) win deals on **short-lived credentials**, **time-bound access**, **SIEM readiness**, **network source control**, **tamper-evident audit**, and **continuous compliance checks**.

Tier 1 features close the largest CSO objections **without** adding paid-tier scope (no RDP/web UI, no vault, no HA). All remain Security-as-Code: Ansible-declarative, Air Gap compatible, Rocky Linux 9 only.

## What Changes

### 1. SSH User CA + short-lived certificates (Free prod path)

- Complete QA from `ssh-user-ca-qa` and promote to **default prod recommendation**.
- Document cert validity (24–72h prod), renewal SOP, rollback to raw pubkeys.
- Optional Ansible helper for cert path validation (not CA signing — signing stays offline).

### 2. JIT access windows (`valid_from` / `valid_until`)

- Extend `bastion_operators` schema with optional ISO8601 window fields.
- Preflight or runtime gate: deny SSH outside window (sshd + provisioning metadata).
- Scheduled/systemd timer or documented cron: re-run playbook to purge expired operators (integrates with `purge_revoked_operators.yml`).

### 3. SIEM-ready syslog export

- Ansible tasks: rsyslog forwarder config on bastion **host** (not container).
- Structured events: auditd keys + optional sshd/auth log tags documented for client SIEM.
- CEF/JSON format spec in design.md; no proprietary SOC UI.

### 4. Source IP restriction

- Per-operator optional `allowed_sources` (CIDR or IP list).
- Enforce via `from=` in `authorized_keys.j2` and/or firewalld rich rules for `bastion_ssh_port`.
- Preflight warning when prod operators lack source restriction (CSO opt-in strict mode).

### 5. Tamper-evident session logs

- On session log creation: write sidecar `*.log.sha256` with hash + timestamp + operator + incident ref.
- Optional Ansible task: copy closed logs to client WORM mount (`bastion_worm_archive_dir`).
- Document CSO verification procedure (hash re-check before ticket attach).

### 6. Compliance verify (`verify` tag / script)

- `scripts/bastion-compliance-verify.sh` and/or `tasks/verify_compliance_cso.yml`.
- Checks: Rocky 9, SELinux Enforcing, container running, MFA label, whitelist non-empty, no orphan `/home/*` users, auditd active.
- Exit non-zero for monitoring/CI; suitable for CSO demo block.

## Capabilities

### New Capabilities

| Capability | Spec |
|:---|:---|
| SSH User CA (Free prod) | `specs/bastion-ssh-user-ca-prod-free/spec.md` |
| JIT access windows | `specs/bastion-jit-access-windows/spec.md` |
| SIEM syslog export | `specs/bastion-siem-syslog-export/spec.md` |
| Source IP restriction | `specs/bastion-source-ip-restriction/spec.md` |
| Tamper-evident session logs | `specs/bastion-tamper-evident-session-logs/spec.md` |
| Compliance verify | `specs/bastion-compliance-verify/spec.md` |

### Modified Capabilities

- `bastion-ssh-user-ca-trust` (from `ssh-user-ca-qa`) — prod defaults documented; no template change required if QA passes.
- Existing `purge_revoked_operators.yml` — invoked by JIT expiry workflow.

## Impact

- **Tasks:** new `tasks/verify_compliance_cso.yml`, `tasks/configure_rsyslog_siem.yml`, `tasks/configure_jit_timer.yml` (or documented cron), extend `provision_operator_item.yml`, `preflight_cso.yml`
- **Templates:** `authorized_keys.j2`, `bastion-shell-wrapper.sh`, new `rsyslog-bastion.conf.j2`, `systemd/jit-ansible-run.timer.j2` (optional)
- **Scripts:** `scripts/bastion-compliance-verify.sh`, extend `scripts/issue-operator-cert.sh` (optional stub)
- **Group vars:** `all.yml.example` — new operator fields; `bastion_siem_*`, `bastion_jit_*`, `bastion_require_source_ip`
- **Docs:** Whitepaper Control Matrix, CSO Demo Runbook, Troubleshooting Workflow JIT section

## Non-Goals (remain Paid / commercial tier)

- RDP, web, K8s, DB protocol gateways
- Self-service approval portal / ITSM integration API
- OIDC/SAML/AD as primary IdP
- Credential vault and password injection
- Session video replay UI
- HA clustering and central multi-tenant control plane
- Automated CA signing service (HSM/step-ca) in Free v1 — manual/offline signing only

## Dependencies

- **Blocked partially:** SSH User CA prod Free requires completion of `openspec/changes/ssh-user-ca-qa` (PKI access).
- **Independent:** JIT windows, source IP, SIEM rsyslog, tamper-evident hashes, compliance verify can ship incrementally.

## Success Criteria (CSO)

- [ ] Operator cert max validity ≤ 72h in prod (or documented exception).
- [ ] Operator removed automatically after `valid_until` without manual host edits.
- [ ] Session log hash verifiable and included in incident ticket workflow.
- [ ] Client SIEM receives auditd/session events via syslog (documented mapping).
- [ ] Connection from non-allowed IP fails at SSH or firewall layer.
- [ ] `bastion-compliance-verify.sh` passes on healthy lab deploy; fails on deliberate drift.
