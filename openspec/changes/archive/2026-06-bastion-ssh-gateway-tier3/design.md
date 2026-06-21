## Context

**Problem:** `access: jump` + ProxyJump is the industry-default lightweight pattern but is **insufficient** for clients who must prove **what happened on the target** during vendor support sessions.

**Solution:** Add `access: gateway` — bastion **terminates** the operator SSH session and **originates** a new SSH session to the target (credential broking). All PTY I/O is captured on the bastion host under `audit_log_dir`.

**Market:** Organizations ~200–1000 FTE, no PAM, Linux servers in support scope, regulatory or contractual pressure on **third-party access**. They need a **first controlled contour** — not full СКДПУ.

**Architecture unchanged at host level:** Ansible → Rocky Linux 9 → Rootless Podman → OpenSSH + wrappers.

---

## Goals / Non-Goals

**Goals:**

- **Parity with PAM SSH gateway** on recording, attribution, revoke, JIT — not on video/UI.
- **Client control:** audit role, session kill, SIEM export, declarative policy in Git.
- **No agents on targets** (SSH server on target only — standard admin port).
- **Coexist** with `jump` during migration.

**Non-Goals:**

- Replace client’s future СКДПУ purchase for Windows/RDP estate.
- Kernel-level MAC on targets.

---

## D1: Access modes (canonical model)

| `access` | Use case | Target PTY recorded | Operator sees target key |
|:---|:---|:---:|:---:|
| `jump` | Transparent ProxyJump; automation; low-risk transit | ❌ | N/A (operator may use own key) |
| `gateway` | **Prod interactive** support on Linux targets | ✅ | ❌ |
| `shell` | Gateway-only / four-eyes / break-glass on bastion | ✅ (bastion) | N/A |
| `audit` | Client read-only log review | ❌ | ❌ |

**CSO default policy (recommended):**

```yaml
bastion_prod_require_gateway: false   # v0.6: opt-in; v0.7: recommend true for new prod
bastion_jump_risk_acceptance_required: false  # when true, jump ops need bastion_jump_approved: true
```

---

## D2: SSH gateway — technical design

### D2.1 Connection flow

```text
[Operator laptop]
    |  ssh -p 2222 operator@gateway  (+ MFA)
    v
[Container sshd]
    |  Match User operator → ForceCommand /usr/local/bin/bastion-ssh-gateway-wrapper.sh
    v
[gateway-wrapper.sh]
    |  1. Resolve permit_open ∩ bastion_targets
    |  2. If single target → auto; else interactive menu (numbered list)
    |  3. Register session in /run/bastion/sessions/<id>.json
    |  4. exec script → gateway.sh
    v
[gateway.sh]
    |  ssh -i /etc/bastion/targets/<id>/id_ed25519 \
    |      -p <port> -tt -o StrictHostKeyChecking=yes \
    |      <account>@<host>
    |  (PTY bridged; bytes logged)
    v
[Target host SSH]
```

### D2.2 Why not ProxyJump for gateway mode

ProxyJump keeps bastion as **network relay**. Gateway mode requires **process-level PTY capture** on bastion — only achievable when bastion runs `ssh` client to target.

### D2.3 Target selection UX (v1)

| Targets for operator | Behavior |
|:---|:---|
| 1 entry in `permit_open` | Auto-connect, no prompt |
| 2–20 entries | Numbered menu on stderr, single choice |
| &gt;20 | Menu + prefix filter (document limit) |

Non-interactive CI: **out of scope v1** (future `BASTION_GATEWAY_TARGET=host:port` env from Match SetEnv for break-glass automation only).

### D2.4 sshd configuration

```jinja2
{% elif operator.access == 'gateway' %}
    ForceCommand /usr/local/bin/bastion-ssh-gateway-wrapper.sh
    AllowTcpForwarding no
    PermitTTY yes
```

`authorized_keys`: **no** `restrict,port-forwarding` (operator needs PTY on bastion for gateway shell).

### D2.5 Container packages

Add to `Containerfile`: ensure `openssh-client` present (Alpine: `openssh-client` or full `openssh` client binary). Verify `ssh` in PATH for `bastion` user inside container.

---

## D3: Target inventory schema

```yaml
# group_vars/all.yml (secrets via Ansible Vault)
bastion_targets:
  - id: prod-app-01                    # stable id for paths and logs
    host: 10.0.1.10
    port: 22
    account: bastion_support                # Unix account ON TARGET
    identity_file: "{{ playbook_dir }}/vault/targets/prod-app-01_ed25519"  # Vault-encrypted repo OR host path
    host_key_fingerprint: "SHA256:abcdef..."  # optional pin; preflight warn if absent
    tags: [prod, linux]
    description: "Prod application server 01"

bastion_operators:
  - name: engineer1
    access: gateway
    permit_open:
      - "10.0.1.10:22"                # MUST match a bastion_targets entry
    incident_id: "INC-optional"
```

**Provisioning:**

1. Ansible copies/decrypts identity to `{{ bastion_home }}/targets/<id>/id_ed25519` mode `0600`, owner `bastion`, SELinux `container_file_t`.
2. Mount RO: `.../targets:/etc/bastion/targets:ro,Z`
3. Container entrypoint never copies target keys to operator `$HOME`.

**Preflight:**

- Every `gateway` operator `permit_open` entry MUST resolve to `bastion_targets`.
- Target identity files MUST exist and be unreadable by non-`bastion`.
- Warn if `host_key_fingerprint` missing (MITM risk on first connect).

---

## D4: Target session recording

### D4.1 Log path and naming

```text
/var/log/bastion_sessions/gateway_<INCIDENT>_<OPERATOR>_<TARGETID>_<YYYYMMDD>_<HHMMSS>.log
```

Reuse `_sanitize_incident()` from `bastion-shell-wrapper.sh`. `TARGETID` = `bastion_targets[].id` (sanitized).

### D4.2 Sidecars

Same EXIT trap as shell wrapper: `.sha256`, `.meta` with fields:

```text
SHA256=... UTC=... USER=... INCIDENT=... CLIENT=... TARGET=<id> TARGET_HOST=... TARGET_ACCOUNT=... MODE=gateway
```

### D4.3 Host key verification

`gateway.sh` uses `StrictHostKeyChecking accept-new` **only in lab** (`bastion_gateway_lab_mode: true`). Prod: **require** known_hosts file provisioned per target (`templates/ssh_known_hosts_targets.j2`).

---

## D5: Session control plane

### D5.1 Session registry

Path on **host** (writable by container via mount): `/run/bastion/sessions/` or `{{ bastion_home }}/runtime/sessions/`

```json
{
  "id": "20260616-143022-a1b2",
  "operator": "engineer1",
  "target_id": "prod-app-01",
  "target_host": "10.0.1.10",
  "pid": 12345,
  "started_at": "2026-06-16T14:30:22Z",
  "log_path": "/var/log/bastion_sessions/gateway_..."
}
```

### D5.2 CLI

`/usr/local/bin/bastion-session-ctl` (host script, `podman exec` or sidecar):

```bash
bastion-session-ctl list
bastion-session-ctl kill <session-id>
bastion-session-ctl kill --operator engineer1
```

Ansible tag: `session_kill` with `bastion_session_kill_id` extra var.

### D5.3 JIT integration

On `jit_purge` / expired operator: task reads registry, sends SIGTERM to gateway PIDs, then existing purge.

---

## D6: Gateway command policy

Extend Tier 2 denylist to gateway PTY:

- Source same `/etc/bastion/command_denylist`
- Implement in `gateway.sh` via `ssh -tt` + `bastion-command-policy-rc.sh` injected into remote shell **OR** local PTY tap (preferred: **local** — inspect bytes before write to ssh stdin)

**v1 limitation (document):** local tap catches most interactive commands; escape sequences / subshells — same disclaimer as shell policy.

---

## D7: Structured export (SIEM search)

Append-only JSONL on host: `{{ audit_log_dir }}/sessions.jsonl`

```json
{"event":"gateway_start","ts":"...","operator":"engineer1","target_id":"prod-app-01","incident_id":"INC-1","client":"203.0.113.1:12345","session_id":"..."}
{"event":"gateway_end","ts":"...","session_id":"...","exit_code":0,"log_sha256":"..."}
```

Rsyslog: optional `imfile` on JSONL — **client SIEM config**, not hardcoded.

---

## D8: Jump vs gateway policy

When `bastion_prod_require_gateway: true`:

- Operators with any `permit_open` matching `bastion_prod_target_tags` (default `['prod']`) MUST have `access: gateway`.
- `access: jump` allowed only if `bastion_jump_approved: true` on operator (CSO waiver flag).

When `bastion_jump_risk_acceptance_required: true` and `access: jump`:

- Preflight requires `bastion_jump_approved: true` and documents connect-audit-only limitation.

---

## D9: Lab / mock target

`group_vars/dev/gateway_lab.yml`:

- Second container `gateway_target` (sshd) on Lima network OR static VM `10.89.0.5`
- `bastion_targets` with lab key
- Operator `gateway-lab` with `access: gateway`

Acceptance: gateway session → log file exists → `sha256sum -c` → `bastion-session-ctl list` shows session → kill works.

---

## D10: Phasing

| Phase | Release | Deliverable |
|:---|:---|:---|
| **A** | v0.6.0 | `bastion_targets`, gateway wrappers, recording, sshd/keys |
| **B** | v0.6.1 | Session control plane + JIT kill |
| **C** | v0.6.2 | Gateway command policy + known_hosts strict |
| **D** | v0.6.3 | JSONL export + SIEM doc |
| **E** | v0.6.4 | Jump/gateway preflight policy + client 1-pager |

Phases A+B = **minimum market adoption** gate.

---

## D11: Risks

| Risk | Mitigation |
|:---|:---|
| Target keys on bastion = high value | RO mount, SELinux, 0600, auditd on key read, separate target SA with least privilege |
| Gateway compromise → all targets | Document; recommend per-target keys + no root; network ACL target←bastion only |
| `ssh -tt` latency / escape | Accept; document mosh not supported |
| Operator bypass via `jump` if both enabled | Policy Gate `bastion_prod_require_gateway` |
| StrictHostKeyChecking friction | Provision known_hosts in Ansible |

---

## D12: Comparison anchor (СКДПУ SSH)

| Control | СКДПУ Шлюз SSH | SSH PAM gateway (Tier 3) |
|:---|:---|:---|
| Session video | ✅ | ❌ (TTY + hash) |
| Command log on target | ✅ | ✅ (gateway PTY log) |
| Credential broking | ✅ | ✅ (v1 Ansible Vault files) |
| Live session kill | ✅ | ✅ (session-ctl) |
| No target agent | ✅ | ✅ |
| ФСТЭК / реестр | ✅ | ❌ |
| Security-as-Code / Git policy | ⚠️ | ✅ |
