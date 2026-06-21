## Context

Tier 2 extends SSH PAM after **v0.4.0 (Tier 1 complete)**. Architecture unchanged: Ansible → Rocky Linux 9 → Rootless Podman → OpenSSH + offline TOTP.

All Tier 2 controls are **Security-as-Code** — no SaaS, no agent on target hosts.

## Goals / Non-Goals

**Goals:**

- Reduce CSO fear of **shell role** and **emergency access** without building a PAM portal.
- Improve **forensics traceability** (ticket id in log filename).
- Add **network-layer auth abuse** mitigation on bastion SSH port.

**Non-Goals:**

- Real-time command approval by manager.
- Privileged access to target hosts beyond existing `PermitOpen` / jump model.

---

## D1: Break-glass emergency access

**Decision:** Break-glass is a **labeled operator profile**, not a separate product mode.

```yaml
bastion_break_glass_enabled: false   # prod: explicit CSO opt-in
bastion_break_glass_max_hours: 4     # preflight cap on window length

bastion_operators:
  - name: breakglass-oncall
    pubkey: "..."
    mfa_secret: "..."
    access: shell                      # or jump — CSO choice; shell more common for emergency
    break_glass: true
    incident_id: "INC-2026-9999"     # REQUIRED
    valid_from: "2026-06-15T02:00:00+03:00"
    valid_until: "2026-06-15T06:00:00+03:00"   # REQUIRED; ≤ bastion_break_glass_max_hours
```

**Enforcement:**

1. **Preflight:** reject `break_glass: true` when `bastion_break_glass_enabled: false`; require `incident_id`, `valid_until`, window ≤ max hours.
2. **Provisioning:** write marker file `~/.bastion-break-glass` (informational).
3. **Audit:** extra auditd key `bastion_break_glass_session`; wrapper logs `BREAK_GLASS=1`.
4. **Expiry:** existing `jit_filter_operators.yml` + purge (no new timer).

**Simpler v1:** no live sshd time gate beyond JIT purge (same as Tier 1 JIT).

---

## D2: Shell command policy

**Decision:** Denylist enforced in **ForceCommand wrapper** before interactive bash — jump role unaffected.

```yaml
bastion_shell_command_policy_enabled: true
bastion_shell_command_denylist:
  - 'rm\s+-rf\s+/'
  - 'iptables\s+-F'
  - 'mkfs\.'
  - 'dd\s+if='
  - ':(){ :|:& };:'    # fork bomb (basic)
```

**Implementation sketch:**

- `build/files/bastion-command-policy.sh` — reads denylist from `/etc/bastion/command_denylist` (mounted RO from host).
- `bastion-shell-wrapper.sh` sources policy; uses bash `DEBUG` trap or pre-exec hook to match command line against extended regex list.
- On match: log via `logger -t bastion-deny`, optional auditd, print CSO message to user, do not execute.

**Non-goal v1:** allowlist mode, per-operator policies, AI moderation.

---

## D3: SSH brute-force / rate protection

**Decision:** **Host-level** controls (port published from Podman to host `bastion_ssh_port`).

**Option A (preferred v1):** firewalld rich rule rate limit:

```text
rule family="ipv4" source address="0.0.0.0/0" port port="2222" protocol="tcp"
  limit value="30/m" accept
```

**Option B (optional):** fail2ban jail reading container auth log via `podman logs` or forwarded journal — heavier, document for clients with existing fail2ban ops.

```yaml
bastion_ssh_rate_limit_enabled: false
bastion_ssh_rate_limit_method: firewalld   # firewalld | fail2ban
bastion_ssh_rate_limit_rate: "30/m"
bastion_fail2ban_maxretry: 5
bastion_fail2ban_bantime: 3600
```

**Interaction:** source IP `from=` still primary; rate limit is defense in depth for MFA brute force.

---

## D4: Incident ID in session log filename

**Decision:** Extend existing `BASTION_INCIDENT_ID` env (Tier 1) to **log basename**.

| incident_id set | Filename pattern |
|:---|:---|
| no | `session_${USER}_${YYYYMMDD}_${HHMMSS}.log` (unchanged) |
| yes | `session_${SANITIZED_INCIDENT}_${USER}_${YYYYMMDD}_${HHMMSS}.log` |

**Sanitization:** allow `[A-Za-z0-9._-]` only; max 64 chars; fallback `-` if empty after sanitize.

**Container rebuild required** after wrapper change (`./trusted_download.sh`).

---

## D5: Read-only audit role (`access: audit`)

**Decision:** Third operator access mode alongside `jump` and `shell`.

```yaml
- name: auditor1
  pubkey: "..."
  mfa_secret: "..."
  access: audit
  allowed_sources:
    - "203.0.113.50/32"    # CSO workstation subnet
```

**sshd:**

- `ForceCommand /usr/local/bin/bastion-audit-shell-wrapper.sh`
- `AllowTcpForwarding no`
- No `restrict` in authorized_keys (needs PTY for pager)

**audit-shell-wrapper.sh:**

- Restricted PATH; allowed commands: `less`, `cat`, `ls`, `head`, `tail` (read-only, no `-f` follow if feasible), `grep`, `sha256sum`, `exit`.
- Chroot not required v1; script validates paths under `/var/log/bastion_sessions` only (realpath check).
- Session still recorded via `script` + tamper sidecars (auditor actions auditable).

**Preflight:** `access: audit` forbidden when `is_commercial_pam: true` until PAM branch defined.

---

## Phasing (R&D)

| Phase | Release | Specs |
|:---|:---|:---|
| **A** | v0.5.0 | incident log naming |
| **B** | v0.5.1 | shell command policy |
| **C** | v0.5.2 | audit readonly role |
| **D** | v0.5.3 | SSH rate limit / fail2ban |
| **E** | v0.5.4 | break-glass |

Phases A–C can parallelize; E depends on JIT (Tier 1).

---

## Risks

| Risk | Mitigation |
|:---|:---|
| Command denylist bypass via bash builtins | Document limitation; CSO prefers jump-only prod |
| fail2ban + Podman log parsing fragile | Default to firewalld rate limit |
| Audit role path traversal | realpath + prefix check in wrapper |
| Break-glass misuse | short max window + mandatory incident_id + SIEM alert on key |
