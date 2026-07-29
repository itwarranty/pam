## ADDED Requirements

### Requirement: QA operators MAY authenticate with signed user certificates
When an operator entry uses `certificate` instead of `pubkey`, SSH PAM SHALL write the certificate line to `authorized_keys` and SHALL accept authentication when the certificate is signed by the configured User CA and presents valid principal.

#### Scenario: Jump operator certificate with restrict options
- **WHEN** operator has `access: jump` and `certificate` is defined
- **THEN** `authorized_keys` SHALL prefix the certificate with `restrict,port-forwarding` and `permitopen` entries from `permit_open` or global `pam_permitted_targets`

#### Scenario: Shell operator certificate without restrict
- **WHEN** operator has `access: shell` and `certificate` is defined
- **THEN** `authorized_keys` SHALL contain the certificate without `restrict,port-forwarding`
- **THEN** sshd `Match User` SHALL apply `ForceCommand` wrapper for session recording

#### Scenario: Certificate plus MFA
- **WHEN** operator presents valid user certificate and correct TOTP
- **THEN** SSH authentication SHALL succeed
- **WHEN** operator presents valid certificate but incorrect or missing TOTP
- **THEN** SSH authentication SHALL fail

### Requirement: Certificate naming SHALL follow example.com convention
User certificate issuance for QA SHALL use identities aligned with domain `example.com`.

#### Scenario: Key ID and principal on issuance
- **WHEN** PKI admin signs a user key with `ssh-keygen -s`
- **THEN** Key ID (`-I`) SHALL be `{operator}@example.com`
- **THEN** principal (`-n`) SHALL equal Ansible `operator.name` (Unix username in container)

#### Scenario: Ansible operator email field
- **WHEN** provisioning MFA secrets for QA operators
- **THEN** otpauth labels SHALL use `{operator}@example.com` when `email` or `pam_lab_domain` is set

### Requirement: Standard user certificate issuance command for QA
QA documentation SHALL define the canonical signing command for operator certificates.

#### Scenario: QA certificate creation
- **WHEN** PKI admin issues QA cert for operator `engineer-jump`
- **THEN** signing SHALL follow:
  ```bash
  ssh-keygen -s /secure/user-ca \
    -I "engineer-jump@example.com" \
    -n engineer-jump \
    -V +30d \
    -O clear \
    ~/.ssh/gateway-qa.pub
  ```
- **THEN** resulting `*-cert.pub` MAY be copied to `lab/certs/engineer-jump-cert.pub` for Ansible lookup
