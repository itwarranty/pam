### Requirement: Operators MAY authenticate via short-lived SSH certificates from IdP-gated signing

SSH PAM SHALL document and support OIDC-gated operator certificate issuance for production.

#### Scenario: Prod with OIDC policy
- **WHEN** `bastion_oidc_cert_policy_enabled: true`
- **AND** operator is production operator
- **THEN** preflight SHALL require `operator.certificate` (not raw `pubkey`) unless CSO waiver flag documented

#### Scenario: Offline signing workflow
- **WHEN** admin runs `scripts/sign-operator-cert-oidc.sh.example` with valid OIDC ID token or offline refresh
- **THEN** script SHALL verify `bastion_oidc_required_group` claim
- **THEN** script SHALL invoke `ssh-keygen -s` with validity ≤ `bastion_cert_max_validity_hours`
- **THEN** output cert SHALL be placeable in `operator.certificate` for Ansible deploy

#### Scenario: Air Gap bastion
- **WHEN** bastion host has no Internet
- **THEN** IdP interaction SHALL occur only on admin workstation (documented)
- **THEN** bastion SHALL validate certs via existing TrustedUserCAKeys only

### Requirement: OIDC configuration SHALL be declarative

#### Scenario: group_vars
- **WHEN** OIDC policy enabled
- **THEN** `bastion_oidc_issuer`, `bastion_oidc_client_id`, `bastion_oidc_required_group` SHALL be documented in `all.yml.example`

### Requirement: SAML SHALL have documented bridge path

#### Scenario: SAML-only IdP
- **WHEN** client uses SAML IdP
- **THEN** documentation SHALL describe supported path (e.g. Keycloak OIDC broker or `saml2aws` example script)
- **THEN** full SAML SP implementation in bastion container is NOT required

### Requirement: OIDC SHALL NOT replace MFA on bastion by default

#### Scenario: Default policy
- **WHEN** operator uses certificate from OIDC signing
- **THEN** sshd `AuthenticationMethods publickey,keyboard-interactive` SHALL remain unless CSO sets `bastion_mfa_enforce: false` with waiver
