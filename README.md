# ITWarranty SSH PAM

**Repository:** [github.com/itwarranty/pam](https://github.com/itwarranty/pam)

Open-source **SSH Privileged Access Management** from [ITWarranty](https://github.com/itwarranty): audited remote access for support engineers into Air Gap / Linux perimeters — gateway, MFA, JIT, session recording, Security-as-a-Code (Rootless Podman, CSO Policy Gate).

## Quick start (dev)

```bash
./scripts/dev-up.sh
```

## Admin tools

```bash
# Test access (Git + gateway, onboarding + QR)
./scripts/test-repo-key.sh create <name> --pam --apply
./scripts/test-repo-key.sh revoke <name> --apply      # declarative purge + restart
./scripts/test-repo-key.sh apply-dev

# Compliance verify (Tier 1 — post-deploy)
./scripts/pam-compliance-verify.sh
./scripts/pam-doctor.sh engineer-jump   # lab: role, TOTP, ProxyJump hint
ansible-playbook -i inventory/local-lima.yml site.yml --tags verify_compliance

# Gateway session control (Tier 3)
pam-session-ctl list
ansible-playbook -i inventory/local-lima.yml site.yml --tags session_kill -e pam_session_kill_id=<id>

# Session search / watch (Tier 4)
pam-session-search --operator engineer1 --since 7d
pam-session-watch <session-id>

# GitHub account access
./scripts/repo-access.sh grant <github_user>
./scripts/repo-access.sh revoke <github_user>
```

## Documentation

| Document | Description |
| :--- | :--- |
| [docs/README.md](docs/README.md) | Docs index |
| [Engineer Onboarding](docs/Engineer-Onboarding.md) | Repo access + dev stand |
| [Whitepaper](docs/Whitepaper.md) | CSO technical passport |
| [Troubleshooting Workflow](docs/Troubleshooting-Workflow.md) | Incident playbook |
| [CSO Demo Runbook](docs/CSO-Demo-Runbook.md) | Presales demo |
| [SSH PAM Overview](docs/SSH-PAM-Overview.md) | Customer positioning |
| [FIDO Onboarding](docs/FIDO-Onboarding.md) | FIDO-sk + TOTP (Tier 5) |
| [Battlecard vs СКДПУ SSH](docs/Battlecard-SKDPU-SSH.md) | Presales comparison |
| [HA Runbook](docs/HA-Runbook.md) | Active-passive failover |
| [OpenSpec specs](openspec/specs/) | GA specs Tier 1–5 |
| [OpenSpec archive](openspec/changes/archive/) | Completed change history |

## Prod deploy

1. Fill `pam_operators` in `group_vars/all.yml` (Vault).
2. Build image: `./trusted_download.sh` → copy tar into Air Gap.
3. `ansible-galaxy collection install -r requirements.yml`
4. `ansible-playbook -i inventory/hosts.yml site.yml`

Revoke access: remove the operator from `pam_operators` and re-run the playbook (`purge_revoked_operators.yml`).

## Releases

| Tag | Content |
| :--- | :--- |
| `v0.2.0` | Tier 1 Phase A — compliance, tamper logs, source IP, SIEM |
| `v0.4.0` | Tier 1 Phase B + C — JIT, SSH User CA policy |
| `v0.5.0` | Tier 2 — incident naming, denylist, audit, rate limit, break-glass |
| `v0.6.0` | Tier 3 — SSH gateway, target recording, session-ctl |
| **`v1.0.0`** | **Tier 4 — SSH PAM GA:** search, policy v2, watch, Vault, OIDC examples, HA |
| **`v1.1.0`** | **Tier 5 — FIDO-Anchor MFA:** `ed25519-sk` + TOTP, JIT sk certs |

## Commercial

Need deployment, SLA, or multi-protocol PAM? Contact [ITWarranty](https://github.com/itwarranty).

## CI

GitHub Actions: syntax-check `site.yml` (`.github/workflows/ci.yml`).
