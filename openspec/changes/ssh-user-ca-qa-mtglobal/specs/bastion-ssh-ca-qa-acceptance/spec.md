## ADDED Requirements

### Requirement: QA enablement SHALL use dedicated inventory and group vars
QA SSH User CA testing SHALL NOT alter default lab raw-key configuration.

#### Scenario: QA group isolation
- **WHEN** QA testing begins
- **THEN** configuration SHALL live in `group_vars/qa_mtglobal.yml` and inventory group `qa_mtglobal`
- **THEN** `group_vars/local_lima.yml` SHALL remain on raw pubkeys until QA sign-off

#### Scenario: QA template files exist
- **WHEN** engineer prepares QA environment
- **THEN** QA configuration examples SHALL be documented in `openspec/changes/ssh-user-ca-qa-mtglobal/design.md`

### Requirement: QA acceptance tests SHALL validate CA authentication paths
Before CSO sign-off for prod CA mode, QA SHALL execute the following verifications.

#### Scenario: Valid certificate authentication succeeds
- **WHEN** operator connects with valid cert, matching private key, and valid TOTP
- **THEN** authentication SHALL succeed

#### Scenario: Expired certificate is rejected
- **WHEN** operator presents expired user certificate
- **THEN** authentication SHALL fail

#### Scenario: Wrong principal is rejected
- **WHEN** certificate principal does not match container Unix username
- **THEN** authentication SHALL fail

#### Scenario: Jump direct shell remains blocked with certificate
- **WHEN** jump operator runs interactive `ssh engineer-jump@bastion` without ProxyJump
- **THEN** PTY/shell allocation SHALL fail (restrict in authorized_keys)

#### Scenario: ProxyJump to whitelist succeeds
- **WHEN** jump operator uses `ssh -J` to a host in `permit_open`
- **THEN** forwarded connection SHALL be permitted per sshd policy

### Requirement: Rollback from CA mode SHALL be supported without image rebuild
MT: Bastion SHALL allow reverting QA/prod from certificates to raw pubkeys via Ansible only.

#### Scenario: Rollback procedure
- **WHEN** operator removes `bastion_trusted_user_ca_file` and restores `pubkey` fields
- **THEN** `ansible-playbook site.yml` SHALL restore raw-key authentication
- **THEN** container image SHALL NOT require rebuild

### Requirement: Prod CA cutover SHALL require CSO gates beyond QA
Production use of SSH User CA SHALL NOT proceed until QA acceptance and CSO approval are recorded.

#### Scenario: Prod constraints
- **WHEN** moving to prod CA mode
- **THEN** certificate validity SHALL NOT exceed 72 hours unless CSO documents exception
- **THEN** user certificates SHALL NOT be committed to git
- **THEN** CA public key SHOULD be sourced from Vault or secure controller path, not lab tree
