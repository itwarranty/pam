### Requirement: Target SSH keys MAY be sourced from HashiCorp Vault at deploy time

MT Bastion SHALL support external secret store for `bastion_targets` credentials without runtime Vault dependency in container.

#### Scenario: Vault path configured
- **WHEN** target entry has `vault_secret_path` and `bastion_vault_enabled: true`
- **THEN** Ansible SHALL fetch private key from Vault KV v2 on controller during provision
- **THEN** key SHALL be written to `{{ bastion_home }}/targets/<id>/identity` with mode 0600
- **THEN** container SHALL mount key read-only as today

#### Scenario: Mutual exclusion with identity_file
- **WHEN** both `vault_secret_path` and `identity_file` are set on same target
- **THEN** preflight SHALL fail

#### Scenario: Vault disabled
- **WHEN** `bastion_vault_enabled` is `false`
- **THEN** only `identity_file` / Ansible Vault paths SHALL be used

### Requirement: Vault tokens SHALL NOT be mounted into container

#### Scenario: Deploy
- **WHEN** Vault fetch succeeds
- **THEN** Vault token SHALL remain on Ansible controller only
- **THEN** running container SHALL NOT contain Vault token or API client config

### Requirement: Air Gap SHALL remain supported

#### Scenario: No Vault connectivity from bastion host
- **WHEN** Ansible controller can reach Vault but bastion host cannot
- **THEN** deploy SHALL still succeed (render-at-deploy model)

### Requirement: collection dependency SHALL be documented

#### Scenario: Enable Vault
- **WHEN** `bastion_vault_enabled: true`
- **THEN** `requirements.yml` SHALL include `community.hashi_vault` collection
- **THEN** Engineer Onboarding SHALL document token policy
