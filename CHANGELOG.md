# Changelog

## v1.1.0 — FIDO-Anchor MFA (Tier 5)

- FIDO2 / platform SSH keys (`ed25519-sk -O verify-required`) as first factor
- MFA modes: `totp`, `fido_totp`, `fido_only` (CSO waiver)
- Preflight + compliance verify `fido_pubkey`
- JIT certificate signing for FIDO keys (`sign-operator-cert-jit.sh.example`)
- FIDO onboarding doc, Policy Gate #32–33

## v1.0.0 — SSH PAM GA (Tier 4)

- Session search CLI (`bastion-session-search`)
- Gateway/shell command policy v2 (bastion-side PTY inspector)
- Live session moderation (`bastion-session-watch`)
- HashiCorp Vault target keys (render-at-deploy)
- OIDC/SAML cert signing examples
- HA active-passive runbook + Ansible vars
- PAM positioning docs (`MT-Dostup-SSH-PAM-Overview.md`), battlecard, SoW

## v0.6.0 — Tier 3 SSH Gateway

- `access: gateway`, target recording, `bastion-session-ctl`

## v0.5.0 — Tier 2

- Command denylist, audit role, break-glass, rate limit

## v0.4.0 — Tier 1 B+C

- JIT windows, SSH User CA policy

## v0.2.0 — Tier 1 A

- Compliance verify, tamper logs, SIEM hook

## v0.1 — Baseline

- Policy Gate, MFA, declarative revoke
