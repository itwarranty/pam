## Why

SSH PAM **v0.5.0** (Tier 1 + Tier 2) delivers strong **bastion-side** controls: MFA, JIT, purge, tamper-evident logs, SIEM hook, audit role, break-glass. For the market segment **without PAM** (~200–1000 employees, Linux-heavy support contracts), adoption stalls on one CSO question:

> «Что делал инженер **на целевом сервере** при инциденте?»

Current `access: jump` uses OpenSSH **transparent TCP forwarding** (`restrict` + ProxyJump). The bastion audits **connection metadata** (auditd, sshd VERBOSE) but **not the PTY byte stream on the target**. Enterprise PAM (e.g. СКДПУ НТ Шлюз доступа) records full SSH sessions to target systems.

**Tier 3 (SSH Gateway)** closes the adoption gap for SSH-only clients **without** adding RDP, web portals, or multi-protocol PAM. Jump remains for low-risk transit; **gateway becomes the recommended prod mode** for interactive work on targets.

## What Changes

### 1. New access mode: `access: gateway`

- Operator authenticates to gateway (key/cert + MFA) as today.
- `ForceCommand` invokes **SSH session proxy** — bastion opens a **second** SSH session to the target using **broked credentials**.
- Operator receives a PTY; all bytes recorded on bastion host with tamper-evident sidecars (reuse Tier 1/2 patterns).

### 2. Target inventory and credential broking

- Declarative `bastion_targets[]` (host, port, service account, key path or Ansible Vault ref).
- Target private keys **never** in git plaintext; mounted read-only into container.
- Operator **never** receives target private keys or passwords.

### 3. Target session recording

- Log naming: `gateway_<INCIDENT>_<OPERATOR>_<TARGET>_<YYYYMMDD>_<HHMMSS>.log`
- `.sha256` + `.meta` sidecars; optional WORM archive (existing task).
- Structured JSONL event stream (session start/end, target, operator) for SIEM search.

### 4. Session control plane

- Host-local registry of active gateway sessions (PID, operator, target, start time).
- CLI `bastion-session-ctl list|kill` (and Ansible tag `session_kill`) for client CSO.
- JIT purge / break-glass expiry SHALL terminate active gateway sessions when implemented.

### 5. Jump vs gateway policy (CSO Policy Gate)

- New preflight modes: `bastion_prod_require_gateway` — prod operators with `permit_open` on prod targets MUST use `access: gateway`, not `jump`.
- Documented risk acceptance for `jump` (connect-audit only).

### 6. Target command policy (extends Tier 2)

- Apply denylist (and future allowlist) to **gateway** PTY stream, not only `access: shell` on bastion.

### 7. Market adoption artifacts

- Client-facing 1-pager «Первый контур без PAM» (Russian).
- CSO Demo Runbook block: gateway session + log verify + session kill.
- Lab fixture `group_vars/dev/gateway_lab.yml` with mock target (container or Lima VM).

## Capabilities

### New Capabilities

| Capability | Spec |
|:---|:---|
| SSH gateway access mode | `specs/bastion-ssh-gateway-mode/spec.md` |
| Target session recording | `specs/bastion-target-session-recording/spec.md` |
| Target credential broking | `specs/bastion-target-credential-brokering/spec.md` |
| Session control plane | `specs/bastion-session-control-plane/spec.md` |
| Jump vs gateway CSO policy | `specs/bastion-jump-gateway-access-policy/spec.md` |
| Gateway command policy | `specs/bastion-gateway-command-policy/spec.md` |
| Structured session export | `specs/bastion-session-structured-export/spec.md` |

### Modified Capabilities

- `bastion-tamper-evident-session-logs` — gateway log basename pattern.
- `bastion-jit-access-windows` — purge kills active gateway sessions.
- `bastion-compliance-verify` — gateway smoke check when enabled.
- `bastion-siem-syslog-export` — JSONL path documented in appendix.
- `bastion-audit-readonly-role` — auditors MAY read gateway logs (unchanged path).

## Impact

- **Build:** `bastion-ssh-gateway-wrapper.sh`, `bastion-ssh-gateway.sh`, `bastion-session-ctl.sh`, extend `Containerfile`
- **Tasks:** `provision_bastion_targets.yml`, `configure_gateway_policy.yml`, extend `deploy_ssh_bastion.yml` mounts
- **Templates:** `sshd_config.j2`, `authorized_keys.j2`, `bastion_targets.schema` in example vars
- **Group vars:** `bastion_targets`, `bastion_prod_require_gateway`, `bastion_gateway_*`
- **Docs:** Whitepaper §4 scenario C, Policy Gate #26–28, client 1-pager

## Non-Goals (remain Paid / SSH PAM / out of scope)

- RDP, VNC, web, database protocols
- Self-service approval portal / ITSM API
- OIDC/SAML/AD as primary IdP (future Tier 4)
- External HashiCorp/Vault dynamic secrets API (Free: Ansible Vault file paths only)
- HA clustering, central multi-tenant control plane
- Video replay UI; proprietary session indexer SaaS
- ФСТЭК product certification (organizational track)

## Dependencies

- Tier 1: tamper-evident logs, JIT purge, SIEM, compliance verify
- Tier 2: incident log naming, command policy patterns, audit role
- Container rebuild via `trusted_download.sh` after wrapper changes

## Success Criteria (CSO + market)

- [ ] Operator with `access: gateway` completes interactive SSH to whitelisted target; full TTY log on bastion host.
- [ ] Operator cannot obtain target private key material via bastion.
- [ ] Client auditor (`access: audit`) verifies gateway log hash without infrastructure access.
- [ ] CSO kills active gateway session via `bastion-session-ctl kill` in &lt; 60s documented procedure.
- [ ] `jump` and `gateway` coexist; preflight enforces gateway for prod when `bastion_prod_require_gateway: true`.
- [ ] Lab demo reproducible on `inventory/local-lima.yml` + `gateway_lab.yml`.
- [ ] Adoption checklist: company without PAM can deploy and answer auditor five questions (who/when/where/what/revoke).
