## Why

SSH PAM lab uses raw SSH public keys in `authorized_keys`. That is sufficient for local development but weaker for CSO audit: no centralized revocation, long-lived credentials, no org-bound identity chain.

The playbook already supports SSH User CA (`TrustedUserCAKeys`, operator `certificate` field) but the organization CA for `example.com` is not yet available. QA must define and gate the transition to CA-signed user certificates without blocking current lab work.

## What Changes

- Document and enforce QA workflow for SSH User CA `example.com`.
- Enable `pam_trusted_user_ca_file` and operator certificates in QA inventory/group vars.
- Define naming conventions (`{user}@example.com`), certificate validity, and issuance commands.
- Add QA acceptance scenarios (valid cert, expired cert, wrong principal, jump restrict).
- Define prod cutover and rollback to raw pubkeys.
- Keep lab on raw keys until QA sign-off.

## Capabilities

### New Capabilities

- `gateway-ssh-user-ca-trust`: deploy org User CA public key to sshd `TrustedUserCAKeys` inside the gateway container.
- `gateway-ssh-user-cert-operators`: authenticate operators via signed user certificates with `@example.com` identity and existing MFA/TOTP controls.
- `gateway-ssh-ca-qa-acceptance`: QA checklist, security constraints, rollback, and prod readiness gates.

### Modified Capabilities

- None (implementation hooks already exist in Ansible templates/tasks).

## Impact

- Affected configuration:
  - `group_vars/qa.yml` (from `.example`)
  - `inventory/qa.yml`
  - `lab/ca/user-ca.pub`
  - `lab/certs/*-cert.pub` (gitignored)
- Affected code (no changes required for QA enablement):
  - `templates/sshd_config.j2`
  - `templates/authorized_keys.j2`
  - `tasks/deploy_ssh_pam.yml`
- Documentation:
  - OpenSpec change `ssh-user-ca-qa` (single source for QA SSH User CA)

## Non-Goals

- Host CA / `HostCertificate` for gateway hostname (optional future hardening).
- Replacing TOTP with CA (MFA remains mandatory).
- Automated cert renewal pipeline in v1 QA (manual `ssh-keygen -s` is acceptable for QA).
