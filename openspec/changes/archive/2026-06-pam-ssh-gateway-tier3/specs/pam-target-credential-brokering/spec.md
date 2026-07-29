### Requirement: Target credentials SHALL be declared separately from operators

SSH PAM SHALL maintain `pam_targets` inventory distinct from `pam_operators`.

#### Scenario: Target inventory entry
- **WHEN** `pam_targets` contains an entry with `id`, `host`, `port`, `account`, `identity_file`
- **THEN** Ansible SHALL provision identity to `{{ pam_home }}/targets/<id>/` on the gateway host
- **THEN** identity file permissions SHALL be `0600` and owner `pam_user`

#### Scenario: Gateway resolves credentials
- **WHEN** gateway connects to target
- **THEN** ssh client SHALL use `/etc/ssh-pam/targets/<id>/identity` (or documented path) inside container
- **THEN** operator home directory SHALL NOT contain target private keys

### Requirement: Target private keys SHALL NOT be stored in git plaintext

#### Scenario: Preflight on prod deploy
- **WHEN** `identity_file` points to a path under playbook tree
- **AND** file is not Ansible Vault encrypted
- **THEN** preflight SHALL fail or warn per `pam_require_vault_target_keys` (default `true` for prod)

### Requirement: Operators SHALL NOT receive target secrets at login

#### Scenario: Operator authenticates to gateway
- **WHEN** gateway session starts
- **THEN** operator SHALL NOT see target private key material in environment, files, or ForceCommand output

### Requirement: Target SSH host keys SHALL be verified in production

#### Scenario: Production deploy
- **WHEN** `pam_gateway_lab_mode` is `false` (default)
- **THEN** gateway ssh client SHALL use known_hosts provisioned from `pam_targets[].host_key_fingerprint` or managed known_hosts file
- **THEN** MITM downgrade to `accept-new` SHALL NOT occur in prod

#### Scenario: Lab mode
- **WHEN** `pam_gateway_lab_mode` is `true`
- **THEN** relaxed host key policy MAY be used with documented CSO lab-only warning

### Requirement: Target service accounts SHALL use least privilege

Documentation SHALL require target accounts dedicated to gateway (not shared root) where possible.

#### Scenario: CSO review
- **WHEN** client reads Whitepaper gateway section
- **THEN** documentation SHALL recommend non-root `account` on target with sudo audit on target side (client responsibility)
