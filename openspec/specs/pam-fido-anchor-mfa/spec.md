## ADDED Requirements

### Requirement: SSH PAM SHALL support FIDO2-bound SSH operator keys as phishing-resistant first factor

Production deployments MAY require operators to use OpenSSH security key types (`sk-ssh-ed25519@openssh.com` or optionally `sk-ecdsa-sha2-nistp256@openssh.com`) with user verification.

#### Scenario: Recommended key generation
- **WHEN** CSO enables FIDO anchor policy for an operator
- **THEN** documentation SHALL instruct:
  ```bash
  ssh-keygen -t ed25519-sk -O verify-required -C "operator@example.com" -f ~/.ssh/gateway-fido
  ```
- **THEN** operator SHALL register the resulting `.pub` in `pam_operators[].pubkey` via Ansible

#### Scenario: Platform authenticator on macOS
- **WHEN** operator uses Apple Secure Enclave / Touch ID backed sk key
- **THEN** authentication SHALL require user verification on each SSH connection attempt (touch/biometric or PIN per OS)
- **THEN** gateway SHALL NOT implement biometric APIs — verification is client-side only

#### Scenario: Hardware security key on Linux
- **WHEN** operator uses YubiKey or similar with `ed25519-sk`
- **THEN** same `verify-required` policy SHALL apply

### Requirement: FIDO pubkey requirement SHALL be declarative and enforceable at preflight

#### Scenario: Default off for backward compatibility
- **WHEN** `pam_require_fido_pubkey` is unset or `false`
- **THEN** deploy SHALL accept legacy non-sk pubkeys (subject to existing `pam_allow_raw_pubkey_prod` / certificate rules)

#### Scenario: Prod strict mode
- **WHEN** `pam_require_fido_pubkey: true`
- **AND** operator uses `pubkey` (not empty)
- **THEN** preflight SHALL fail if pubkey does not start with `sk-ssh-ed25519@openssh.com` (or allowed ecdsa-sk when `pam_fido_ecdsa_sk_allowed: true`)

#### Scenario: Certificate backed by FIDO key
- **WHEN** `pam_require_fido_pubkey: true`
- **AND** operator uses `certificate`
- **THEN** preflight SHALL verify via `ssh-keygen -Lf` that certificate is bound to sk key type
- **THEN** deploy SHALL fail if certificate is not FIDO-backed

#### Scenario: CSO waiver for non-FIDO
- **WHEN** `pam_require_fido_pubkey: false` with explicit `pam_fido_waiver_operators: [name]` documented
- **THEN** preflight MAY allow listed operators to use non-sk keys (migration only; warn in debug)

### Requirement: TOTP on the gateway SHALL remain mandatory unless explicit fido_only waiver

FIDO strengthens the **first** factor; offline TOTP remains the default **second** factor.

#### Scenario: Default MFA mode fido_totp
- **WHEN** `pam_mfa_mode: fido_totp` (recommended prod)
- **THEN** `AuthenticationMethods` SHALL remain `publickey,keyboard-interactive`
- **THEN** PAM `pam_google_authenticator.so` SHALL remain required (MFA_STRICT=1)

#### Scenario: Legacy totp mode
- **WHEN** `pam_mfa_mode: totp`
- **THEN** behavior SHALL match v1.0.0 (any allowed pubkey/cert + TOTP)

#### Scenario: fido_only mode gated
- **WHEN** `pam_mfa_mode: fido_only`
- **AND** `pam_fido_only_waiver` is not `true`
- **THEN** preflight SHALL fail
- **WHEN** `pam_fido_only_waiver: true` AND `pam_require_fido_pubkey: true`
- **THEN** sshd MAY use `AuthenticationMethods publickey` only (no keyboard-interactive)
- **THEN** Whitepaper and prod.yml.example SHALL document CSO review requirement

### Requirement: Compliance verify SHALL include FIDO policy checks when enabled

#### Scenario: fido_pubkey check
- **WHEN** `pam_require_fido_pubkey: true` on deployed host
- **THEN** `scripts/pam-compliance-verify.sh` SHALL verify all configured operators use FIDO-sk pubkeys or FIDO-backed certificates
- **THEN** failure SHALL increment non-zero exit code with label `fido_pubkey`

#### Scenario: Ansible verify tag parity
- **WHEN** `ansible-playbook site.yml --tags verify_compliance`
- **THEN** `tasks/verify_compliance_cso.yml` SHALL include equivalent FIDO checks

### Requirement: JIT SSH user certificates SHALL support FIDO operator keys and validity windows

#### Scenario: Sign cert for sk pubkey with JIT window
- **WHEN** admin runs `scripts/sign-operator-cert-jit.sh.example` with operator YAML `valid_from` / `valid_until`
- **THEN** script SHALL produce certificate with `-V` matching JIT window (≤ `pam_cert_max_validity_hours` unless CSO extends)
- **THEN** resulting cert SHALL authenticate with touch/PIN on sk private key plus TOTP (unless fido_only)

#### Scenario: Cert plus MFA unchanged
- **WHEN** operator presents FIDO-backed user certificate and correct TOTP
- **THEN** SSH authentication SHALL succeed
- **WHEN** correct cert but missing TOTP in fido_totp mode
- **THEN** SSH authentication SHALL fail

### Requirement: Lab contour SHALL NOT require FIDO by default

#### Scenario: Dev operators
- **WHEN** deploying with `group_vars/dev/`
- **THEN** `pam_require_fido_pubkey` SHALL default to `false`
- **THEN** existing `engineer-jump.lab` / `engineer-shell.lab` keys SHALL continue to work

#### Scenario: Optional FIDO lab operator
- **WHEN** `pam_fido_lab_enabled: true` and sk key generated
- **THEN** `engineer-fido` operator MAY be merged for manual FIDO+TOTP demo

### Requirement: Documentation SHALL define CSO-auditable positioning vs Teleport FIDO

#### Scenario: FIDO onboarding doc
- **WHEN** change is complete
- **THEN** `docs/FIDO-Onboarding.md` SHALL exist with: key generation, Ansible registration, pilot rollout, waiver process, audit wording

#### Scenario: Policy Gate update
- **WHEN** Whitepaper is updated
- **THEN** Policy Gate rows SHALL document `pam_require_fido_pubkey` and `pam_mfa_mode`
