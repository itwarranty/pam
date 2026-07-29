## Why

SSH PAM **v0.6.0** (Tiers 1–3) delivers complete **SSH PAM core**: gateway recording on targets, credential broking, JIT, MFA, session kill, SIEM/JSONL, audit role, break-glass, jump/gateway policy.

Remaining gaps vs commercial PAM gateways (СКДПУ SSH, CyberArk SSH) are **operational and enterprise ergonomics**, not missing protocol support. Because **SSH PAM is SSH-only PAM** (not a slice missing RDP), these capabilities belong in **SSH PAM** — not a separate paid SSH tier.

**Tier 4** closes the SSH PAM parity gap for **v1.0 GA** (internal prod at  + customer self-host).

## What Changes

### 1. Session search CLI (`pam-session-search`)

- Query `sessions.jsonl` + gateway/shell log metadata by operator, target, date, incident_id, free-text.
- Human table output + `--json` for SIEM scripts.
- No proprietary database — files on the gateway host only.

### 2. Gateway command policy v2 (local PTY inspector)

- Replace remote `bash --rcfile` injection with **gateway-side PTY tap** (pipe/expect-class) for gateway sessions.
- Denylist + optional allowlist; deny logs + optional auto-kill session.
- Same policy file `/etc/ssh-pam/command_denylist`.

### 3. Live session moderation

- `pam-session-watch <session-id>` — read-only live tail of active gateway PTY log for client moderator (`access: audit` or dedicated `access: moderator` — **decision: extend audit role** with watch permission).
- Optional notify via syslog when moderator attaches.

### 4. External secrets (HashiCorp Vault)

- `pam_targets[].vault_path` fetches SSH private key at provision time (Ansible `community.hashi_vault`).
- Ansible Vault remains default; Vault is opt-in.
- No Vault agent in container at runtime (Air Gap friendly: render files at deploy).

### 5. OIDC/SAML → short-lived SSH user certificates

- Optional IdP integration for **operator** authentication material (not target keys).
- Flow: OIDC device/offline token exchange on admin workstation → sign user cert with org User CA → `operator.certificate` (existing path).
- Air Gap: offline signing helper + documented token export; no gateway→IdP runtime dependency required in prod.

### 6. HA active-passive (two gateway hosts)

- Documented + Ansible role pattern: primary/secondary Rocky 9 hosts, shared WORM/NFS for `audit_log_dir`, floating IP or DNS failover.
- Session registry not replicated live (limitation documented); new sessions on standby after failover.
- Not full active-active (out of scope).

### 7. GA v1.0 release engineering

- Complete PKI QA checklist (sibling change).
- `group_vars/prod.yml.example` recommended profile.
- PAM positioning docs (rename client 1-pager).
- `CHANGELOG.md`, compliance script gateway checks.
- CSO battlecard vs СКДПУ (SSH).

## Capabilities

| Capability | Spec |
|:---|:---|
| Session search CLI | `specs/pam-session-search/spec.md` |
| Gateway command policy v2 | `specs/pam-gateway-command-policy-v2/spec.md` |
| Live session moderation | `specs/pam-live-session-moderation/spec.md` |
| External secrets (Vault) | `specs/pam-external-secrets-vault/spec.md` |
| OIDC/SAML SSH user certs | `specs/pam-oidc-saml-ssh-certificates/spec.md` |
| HA active-passive | `specs/pam-ha-active-passive/spec.md` |
| v1.0 GA release | `specs/pam-v1-ga-release/spec.md` |

## Impact

- **Build:** `pam-pty-inspector.sh`, `pam-session-search.sh`, `pam-session-watch.sh`
- **Tasks:** `fetch_vault_target_keys.yml`, `configure_ha_standby.yml`, extend `provision_pam_targets.yml`
- **Scripts:** `scripts/sign-operator-cert-oidc.sh.example`, `scripts/oidc-offline-token.sh.example`
- **Docs:** PAM positioning, battlecard, SoW snippet, CHANGELOG

## Non-Goals

- RDP, VNC, web, database protocols (commercial SSH PAM multi-protocol — separate product line if ever).
- Video replay player UI.
- ФСТЭК certification of product (organizational; not implemented by code tasks).
- Rocky Linux platform change (Astra) — not in Tier 4.
- Active-active session clustering.
- SaaS hosted control plane.

## Agent objections (acknowledged, accepted)

| Concern | Mitigation in Tier 4 |
|:---|:---|
| OIDC complexity in Air Gap | Offline signing path; IdP optional |
| HA without shared storage is weak | Require shared WORM/NFS in HA spec |
| Live watch privacy | Audit role only + syslog + docs |
| Large Free scope | SSH-only boundary keeps scope finite |

## Success Criteria

- [ ] `pam-session-search --operator X --since 7d` returns gateway sessions in &lt;5s on 10k JSONL lines.
- [ ] Gateway denylist blocks `rm -rf /` without remote rc injection (v2 inspector).
- [ ] Moderator with `access: audit` can `pam-session-watch` active session.
- [ ] Target key fetched from Vault path provisions successfully in lab.
- [ ] OIDC example script produces cert ≤72h valid; ssh login works.
- [ ] HA doc + Ansible standby role: failover drill documented.
- [ ] v1.0.0 tag; PKI QA tasks complete; PAM positioning docs published.
