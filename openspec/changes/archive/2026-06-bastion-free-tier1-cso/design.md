## Context

SSH PAM targets **Air Gap / KII** customers who need audited SSH support access without commercial PAM licenses. Architecture stays: Ansible → Rocky Linux 9 host → Rootless Podman → OpenSSH (`sshd.pam`) + offline TOTP.

Tier 1 adds **CSO-visible controls** that enterprise buyers expect, implemented as **declarative code** rather than proprietary agents.

## Goals / Non-Goals

**Goals:**

- Increase Free tier credibility vs Teleport/PAM **for SSH-only support access**.
- Keep all features operable offline after initial deploy (no SaaS dependency).
- Reuse existing purge/restart handlers and Policy Gate patterns.

**Non-Goals:**

- Replace client SIEM or build  hosted analytics.
- Full ITSM workflow engine.

---

## D1: SSH User CA + short-lived certificates

**Decision:** Prod Free recommends user certificates signed by org User CA; raw long-lived pubkeys allowed only in lab (`group_vars/dev/`) until CSO waives.

**Validity:**

| Environment | Max validity | Renewal |
|:---|:---|:---|
| Lab (`dev/`) | raw pubkey OK | n/a |
| QA | ≤ 30 days | manual `ssh-keygen -s` |
| Prod Free | ≤ 72 hours default | manual or client-run signing script |

**Artifacts:**

- CA public: `bastion_trusted_user_ca_file` → container `TrustedUserCAKeys`
- Operator: `operator.certificate` in `authorized_keys` (see existing templates)
- Private CA: never on bastion; signing on admin workstation or client HSM

**Dependency:** Implement trust/certificate specs in `ssh-user-ca-qa` first; this change adds prod policy gates only.

---

## D2: JIT access windows

**Decision:** Optional per-operator fields:

```yaml
bastion_operators:
  - name: engineer1
    pubkey: "..."
    mfa_secret: "..."
    access: jump
    valid_from: "2026-06-15T11:00:00+03:00"   # optional, ISO8601
    valid_until: "2026-06-15T18:00:00+03:00"   # optional
    incident_id: "INC-2026-8942"               # optional, audit metadata
```

**Enforcement layers:**

1. **Provisioning:** write `~/.bastion-access-window` (or extend `.google_authenticator` comment) — informational.
2. **sshd:** `Match User` + `ForceCommand` wrapper that rejects login outside window (shell role) OR `AuthorizedKeysCommand` — **preferred: wrapper script** `bastion-access-window-check.sh` called before auth completes (PAM or ForceCommand pre-check).
3. **Expiry purge:** systemd timer on host runs daily/hourly:

   ```bash
   ansible-playbook site.yml --tags jit_purge
   ```

   Task compares `valid_until` to now; builds ephemeral list excluding expired; triggers `purge_revoked_operators` logic.

**Simpler v1 (recommended first ship):**

- No live sshd time check; **purge-only**: timer removes expired operators from effective config by generating `bastion_operators_active` filter in Ansible.
- Document that connections mid-session may persist until disconnect; new logins blocked after purge + restart.

---

## D3: SIEM syslog export

**Decision:** Configure **host** rsyslog to forward:

| Source | Facility / tag | SIEM use |
|:---|:---|:---|
| auditd (`bastion_*` keys) | `local6` / `bastion-audit` | integrity, connect events |
| `/var/log/bastion_sessions/` write detection | via auditd rule (existing) | session file creation |
| Optional: journald sshd on host | if forwarded | auth failures |

**Template:** `templates/rsyslog-bastion-siem.conf.j2`

```properties
# Example — client replaces @@siem.example:514
local6.*    @@{{ bastion_siem_server }}:{{ bastion_siem_port | default(514) }}
```

**Variables:**

```yaml
bastion_siem_forward_enabled: false
bastion_siem_server: ""
bastion_siem_port: 514
bastion_siem_protocol: tcp   # tcp|udp|relp — document client choice
```

**CEF mapping document** in spec appendix (not implemented parser — client SIEM owns normalization).

---

## D4: Source IP restriction

**Decision:** Optional `allowed_sources` per operator (list of CIDR or single IPs).

**Enforcement (both when configured):**

1. **OpenSSH** — prepend to `authorized_keys.j2`:

   ```
   from="203.0.113.0/24,198.51.100.10",restrict,port-forwarding,... key
   ```

2. **firewalld** (defense in depth) — optional global `bastion_allowed_source_cidrs` rich rule on `bastion_ssh_port`.

**Preflight (strict mode):**

```yaml
bastion_require_source_ip: false   # prod CSO may set true
```

When `true`, every prod operator MUST have non-empty `allowed_sources`.

---

## D5: Tamper-evident session logs

**Decision:** Extend `bastion-shell-wrapper.sh`:

```sh
LOG="/var/log/bastion_sessions/session_${USER}_$(date +%Y%m%d_%H%M%S).log"
META="/var/log/bastion_sessions/session_${USER}_$(date +%Y%m%d_%H%M%S).log.meta"
# ... script session ...
# on exit trap: sha256sum "$LOG" > "${LOG}.sha256"
```

**Sidecar `.sha256` file format (one line):**

```
SHA256=<hex>  UTC=<iso8601>  USER=<user>  INCIDENT=<id or ->  CLIENT=<SSH_CLIENT>
```

**Optional WORM archive (Ansible):**

```yaml
bastion_worm_archive_dir: ""   # e.g. /mnt/worm/bastion/
```

Task copies `*.log` + `*.sha256` when session file mtime stable (document manual or cron sync — avoid race with open session).

---

## D6: Compliance verify

**Decision:** Dual entry points:

1. **Shell script** `scripts/bastion-compliance-verify.sh` — run on bastion host (SSH or lima).
2. **Ansible tag** `verify_compliance` in `tasks/verify_compliance_cso.yml` — same checks remote.

**Checks (minimum):**

| # | Check | Pass condition |
|:-:|:---|:---|
| 1 | OS | Rocky Linux 9.x |
| 2 | SELinux | Enforcing |
| 3 | Container | `ssh_bastion` running as `bastion` |
| 4 | Image label | `bastion.mfa.strict=1` |
| 5 | Whitelist | `bastion_permitted_targets` non-empty in deployed config |
| 6 | Orphan users | no `/home/*` in container outside `bastion_operators` names |
| 7 | auditd | active |
| 8 | firewalld | active, port open |
| 9 | Session log dir | exists, mode 0750, owner bastion |

Exit code 0 = pass; non-zero = fail (usable in Nagios/Prometheus textfile optional later).

---

## Rollout order (recommended)

```text
Phase A (no PKI):  compliance verify → source IP → tamper-evident logs → SIEM template
Phase B:           JIT valid_until + purge timer
Phase C (PKI):     SSH User CA prod Free (after ssh-user-ca-qa QA pass)
```

## Risks

| Risk | Mitigation |
|:---|:---|
| JIT purge mid-session | document; optional `podman restart` after purge |
| SIEM UDP loss | recommend TCP/RELP; client responsibility |
| `from=` breaks roaming engineers | per-operator sources; VPN egress IP documented |
| Clock skew breaks valid_until | NTP requirement in checklist; UTC in vars |

## Open Questions

- [ ] JIT v1: purge-only vs live sshd time rejection?
- [ ] Prod: mandate `bastion_require_source_ip: true` by default?
- [ ] WORM sync: Ansible task vs client cron?
- [ ] Cert renewal: ship `scripts/sign-operator-cert.sh` in repo or external PKI runbook only?
