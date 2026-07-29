## ADDED Requirements

### Requirement: Prod Free tier SHALL recommend SSH user certificates over long-lived raw pubkeys

When CSO Policy Gate is enabled for production deployment, SSH PAM SHALL treat SSH User CA certificates as the preferred authentication material for operators.

#### Scenario: Prod default disallows raw pubkeys without waiver
- **WHEN** `ansible-playbook site.yml` runs for prod inventory
- **AND** `pam_allow_raw_pubkey_prod` is `false` (default)
- **AND** any operator uses `pubkey` without `certificate`
- **THEN** preflight SHALL fail with a message requiring certificate or explicit CSO waiver variable

#### Scenario: Lab and dev remain on raw pubkeys
- **WHEN** playbook runs with `group_vars/dev/` (lab operators)
- **THEN** raw `pubkey` authentication SHALL remain supported
- **THEN** preflight SHALL NOT require certificates

### Requirement: Production user certificate validity SHALL NOT exceed 72 hours by default

SSH PAM prod documentation and preflight SHALL enforce short-lived credentials aligned with CSO expectations.

#### Scenario: Certificate max validity documented
- **WHEN** operator prepares prod certificates via offline signing
- **THEN** signing procedure SHALL use `ssh-keygen -V` window ≤ 72 hours unless `pam_cert_max_validity_hours` override is set with CSO documentation

#### Scenario: Expired certificate rejected at login
- **WHEN** operator presents expired user certificate and valid TOTP
- **THEN** sshd SHALL reject authentication

### Requirement: User CA private key SHALL NOT be deployed to gateway

This requirement is inherited from `gateway-ssh-user-ca-trust` in change `ssh-user-ca-qa`. Tier 1 prod Free SHALL NOT alter that constraint.

#### Scenario: Only CA public key on the gateway
- **WHEN** prod CA mode is enabled
- **THEN** only the User CA **public** key SHALL be present on the gateway host/container

### Requirement: Tier 1 prod Free SHALL depend on completed QA from ssh-user-ca-qa

Production certificate mode SHALL NOT be marked GA until QA acceptance scenarios in sibling change pass.

#### Scenario: QA sign-off gate
- **WHEN** enabling prod certificate mode organization-wide
- **THEN** CSO SHALL record passing results from `gateway-ssh-ca-qa-acceptance` scenarios
