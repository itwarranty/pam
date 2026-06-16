## Context

**Product:** «МТ Доступ» — PAM for SSH. MT: Bastion Free is the open-source tier, **not** a crippled edition. Tier 4 adds enterprise ergonomics that commercial PAM buyers expect, while preserving Security-as-a-Code and Air Gap.

**Internal prod:** MT Global deploys v1.0 on internal Rocky 9; Tier 4 specs must be lab-verifiable on `inventory/local-lima.yml`.

---

## D1: Session search

### Architecture

```text
sessions.jsonl          gateway_*.log.meta / .sha256
       \                       /
        bastion-session-search
              |
    table | --json | --log-path
```

### CLI interface

```bash
bastion-session-search [options]

Options:
  --operator NAME
  --target-id ID
  --target-host IP
  --incident INC-*
  --since 7d|24h|2026-06-01
  --until ISO8601
  --event gateway_start|gateway_end|shell_start
  --grep PATTERN       # search inside .log files (slow; optional)
  --json
  --limit N
```

### Implementation

- Script on **bastion host** (`scripts/bastion-session-search.sh`), reads `audit_log_dir` (default `/var/log/bastion_sessions`).
- Phase 1: JSONL filter with `jq` (required dependency on host — add to Rocky package list in preflight when search enabled).
- Phase 2 optional: index cache `.cache/sessions.idx` rebuilt on gateway_end (future optimization — document in spec as MAY).

### Permissions

- Run as root or `mt_bastion` read-only on log dir; auditors invoke via sudo documented in runbook.

---

## D2: Command policy v2 (PTY inspector)

### Problem with v1

Tier 2/3 inject `bastion-command-policy-rc.sh` **on target** via `ssh -tt ... bash --rcfile`. Issues:

- Requires bash on target; bypass via `/bin/sh -c`, interpreters.
- Policy runs on **target**, not bastion audit boundary.

### Decision: bastion-side PTY proxy

Replace direct `ssh -tt` with wrapper pipeline:

```text
Operator PTY <-> bastion-pty-inspector <-> ssh -tt target
                      |
                 denylist scan on line buffer (before forward to ssh)
```

### Implementation sketch

- `build/files/bastion-pty-inspector.sh` — Python 3 **not** in Alpine container today; use **shell + stty** or add `python3` to Containerfile (prefer **C/shell** for minimal image: use `script` + FIFO + sidecar reader process).
- **Pragmatic v1:** add `python3` to Containerfile (small Alpine package) for `bastion-pty-inspector.py` — readable, testable.
- On deny: log `mt-bastion-deny`, optionally `kill` child ssh if `bastion_gateway_deny_kill_session: true`.

### Variables

```yaml
bastion_gateway_command_policy_v2_enabled: true   # replaces remote rc when true
bastion_gateway_deny_kill_session: false         # CSO opt-in
bastion_shell_command_policy_v2_enabled: true     # same inspector for shell role
```

### Fallback

If v2 disabled, keep v1 remote rc path (backward compatible).

---

## D3: Live session moderation

### Decision

Extend **`access: audit`** with watch capability — no new access enum in v1 (simpler). Optional later: `access: moderator`.

### Flow

```bash
# On bastion host
bastion-session-watch <session-id>    # tail -f active log file from registry
bastion-session-watch --list          # active sessions (delegate to session-ctl)
```

### Security

- Only users with `access: audit` SSH account OR host-side sudo group `mt_bastion_moderators` (documented).
- Log moderator attach: JSONL `event=moderator_watch_start`, syslog.
- Read-only: no inject into PTY (no write to FIFO).

### Limitation

Moderator sees **bastion-recorded log stream** (slight delay vs true video) — document as sufficient for four-eyes.

---

## D4: External secrets (HashiCorp Vault)

### Decision

**Render-at-deploy:** Ansible fetches secret during `provision_bastion_targets.yml`, writes file to host, container mount RO. No live Vault lookup from container (Air Gap + no runtime deps).

### Schema extension

```yaml
bastion_targets:
  - id: prod-db-01
    host: 10.0.1.20
    port: 22
    account: mt_support
    # Option A — Ansible Vault file (existing)
    identity_file: "{{ playbook_dir }}/vault/targets/prod-db-01_ed25519"
    # Option B — HashiCorp Vault (mutually exclusive)
    vault_secret_path: "secret/data/mt-bastion/targets/prod-db-01"
    vault_secret_key: "ssh_private_key"   # default private_key
```

### Ansible

- `tasks/fetch_vault_target_keys.yml` when `bastion_vault_enabled: true`
- Uses `community.hashi_vault.vault_kv2_get` on controller
- Preflight: if `vault_secret_path` set, `identity_file` must not also be set

### Variables

```yaml
bastion_vault_enabled: false
bastion_vault_addr: ""
bastion_vault_token: ""   # Ansible Vault encrypted
bastion_vault_namespace: ""
```

---

## D5: OIDC/SAML → SSH user certificates

### Scope

**Operator authentication** only — replaces long-lived `pubkey` with short-lived `certificate`. Targets still use `bastion_targets` keys.

### Air Gap compatible flow (primary)

```text
[Admin workstation with IdP access]
  1. oidc-offline-token.sh → refresh token (one-time export to secure enclave)
  2. sign-operator-cert-oidc.sh → validates group membership claim → ssh-keygen -s CA
  3. Output *-cert.pub → Ansible operator.certificate → deploy
```

### Online flow (optional, non-Air Gap clients)

- Small `scripts/bastion-oidc-cert-refresh.timer` on engineer laptop — not on bastion.

### Claims mapping

```yaml
bastion_oidc_issuer: "https://idp.example.com/realms/mt"
bastion_oidc_client_id: "mt-bastion-ssh"
bastion_oidc_required_group: "bastion-operators"
bastion_oidc_username_claim: "preferred_username"  # maps to operator.name
```

### Preflight

- When `bastion_oidc_required: true`, all prod operators must use `certificate` not `pubkey`.

### SAML

- v1: document SAML→OIDC bridge (Keycloak) or `sign-operator-cert-saml.sh.example` stub referencing `saml2aws` — full SAML lib out of scope; spec requires **one** documented path.

---

## D6: HA active-passive

### Topology

```text
                    [ VIP or DNS: bastion.example.com ]
                              |
              +---------------+---------------+
              |                               |
      [bastion-primary]              [bastion-standby]
      Rocky 9 + Podman               Rocky 9 + Podman (container stopped or hot standby)
              |                               |
              +------- NFS/WORM shared ---------+
                      audit_log_dir
```

### Ansible

- Inventory groups: `bastion_primary`, `bastion_standby`
- `group_vars/bastion_ha.yml`: shared `audit_log_dir` mount, `bastion_ha_role: primary|standby`
- Standby: `systemctl` timer health check; document manual promotion (`bastion-ha-promote.sh`)

### Limitations (document)

- Active sessions **lost** on failover — kill + reconnect.
- Session registry local — not replicated.
- Split-brain: use VIP + STONITH or manual promotion only.

### Not included

- Automatic Pacemaker/Corosync — client may add; we document requirements.

---

## D7: v1.0 GA release bundle

### PKI QA

Complete `openspec/changes/archive/2026-06-ssh-user-ca-qa-mtglobal/tasks.md` §3–5, 6.2.

### Prod profile

`group_vars/prod.yml.example`:

```yaml
bastion_prod_require_gateway: true
bastion_jit_timer_enabled: true
bastion_siem_forward_enabled: true
bastion_require_source_ip: true
bastion_gateway_command_policy_v2_enabled: true
bastion_ssh_user_ca_qa_complete: true  # after internal QA
```

### Positioning docs

- Rename `MT-Bastion-Client-Without-PAM.md` → `MT-Dostup-SSH-PAM-Overview.md`
- Add `docs/MT-Bastion-Battlecard-SKDPU-SSH.md`
- Add `docs/MT-Bastion-SoW-SSH-Access.md` (snippet)

### Compliance

Extend `bastion-compliance-verify.sh`: gateway manifest, jsonl writable, policy v2 flag optional check.

---

## Phasing

| Phase | Release | Deliverable |
|:---|:---|:---|
| **A** | v0.7.0 | session-search CLI |
| **B** | v0.7.1 | command policy v2 (python inspector) |
| **C** | v0.7.2 | live session-watch |
| **D** | v0.7.3 | HashiCorp Vault fetch |
| **E** | v0.7.4 | OIDC cert signing examples + preflight |
| **F** | v0.7.5 | HA guide + Ansible ha vars |
| **G** | **v1.0.0** | GA docs, PKI QA, CHANGELOG, battlecard |

Phases A–C can ship before D–F; v1.0 requires A–C + PKI QA + positioning docs.

---

## Risks

| Risk | Mitigation |
|:---|:---|
| Python in container increases attack surface | Minimal package; read-only rootfs where possible |
| PTY inspector latency | Accept; document max throughput |
| Vault token on Ansible controller | Vault policy least privilege; doc |
| OIDC scope creep | Examples only on bastion; signing offline |
