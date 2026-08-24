# Changelog

## v1.2.0 — Security hardening (OpenSpec 2026-08)

- Audit role: strict argv executor replaces shell `eval` (`pam-audit-exec.py`)
- Command policy v2: line-gated PTY relay — denied bytes never reach target PTY
- Session control: registry schema v2 with `pgid`; kill uses process group TERM/KILL
- MFA lifecycle: preserve deployed TOTP; bootstrap/rotate are explicit Ansible flags
- Deploy: remove unconditional container `recreate`; block deploy on active sessions
- Live watch: root/moderator authorization; safe log path under `audit_log_dir`
- Audit logs: production `gateway.syslog` / `sessions.jsonl` mode `0640` (`pam-audit` group)
- CI: Python unit tests for audit parser and PTY inspector
- Command policy v1 (`bash --rcfile` on target): requires `pam_command_policy_v1_waiver: true`

## v1.1.1 — Usability (CLI + quickstart)

- Unified `pam` CLI (`pam up|doctor|verify|sessions|access`)
- `scripts/quickstart.sh` / `pam up` for first lab stand
- Deploy profiles: `group_vars/profiles/{eval,pilot,prod}.yml`
- Short [Runbooks](docs/Runbooks.md); README landing + Apache-2.0 LICENSE
- `pam verify --json`; actionable preflight hints

## v1.1.0 — FIDO-Anchor MFA (Tier 5)

- FIDO2 / platform SSH keys (`ed25519-sk -O verify-required`) as first factor
- MFA modes: `totp`, `fido_totp`, `fido_only` (CSO waiver)
- Preflight + compliance verify `fido_pubkey`
- JIT certificate signing for FIDO keys (`sign-operator-cert-jit.sh.example`)
- FIDO onboarding doc, Policy Gate #32–33

## v1.0.0 — SSH PAM GA (Tier 4)

- Session search CLI (`pam-session-search`)
- Gateway/shell command policy v2 (gateway-side PTY inspector)
- Live session moderation (`pam-session-watch`)
- HashiCorp Vault target keys (render-at-deploy)
- OIDC/SAML cert signing examples
- HA active-passive runbook + Ansible vars
- PAM positioning docs (`SSH-PAM-Overview.md`), battlecard, SoW

## v0.6.0 — Tier 3 SSH Gateway

- `access: gateway`, target recording, `pam-session-ctl`

## v0.5.0 — Tier 2

- Command denylist, audit role, break-glass, rate limit

## v0.4.0 — Tier 1 B+C

- JIT windows, SSH User CA policy

## v0.2.0 — Tier 1 A

- Compliance verify, tamper logs, SIEM hook

## v0.1 — Baseline

- Policy Gate, MFA, declarative revoke
