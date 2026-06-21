## ADDED Requirements

### Requirement: QA deployment SHALL configure TrustedUserCAKeys when CA file is provided
When `bastion_trusted_user_ca_file` is set, SSH PAM SHALL install the org User CA public key on the bastion host and expose it to container sshd as `/etc/ssh/trusted_user_ca.pub` with `TrustedUserCAKeys` enabled.

#### Scenario: CA pubkey is copied and mounted
- **WHEN** `ansible-playbook site.yml` runs with non-empty `bastion_trusted_user_ca_file` pointing to a readable `.pub` file
- **THEN** the file SHALL be copied to `{{ bastion_home }}/.ssh_config/trusted_user_ca.pub`
- **THEN** the running container SHALL mount it read-only at `/etc/ssh/trusted_user_ca.pub` with SELinux label `:Z`

#### Scenario: sshd references TrustedUserCAKeys
- **WHEN** the bastion container is running with CA configured
- **THEN** generated `sshd_config` SHALL contain `TrustedUserCAKeys /etc/ssh/trusted_user_ca.pub`

#### Scenario: CA not configured in lab
- **WHEN** `bastion_trusted_user_ca_file` is unset or empty (default lab)
- **THEN** `TrustedUserCAKeys` SHALL NOT appear in sshd_config
- **THEN** deployment SHALL succeed using raw operator pubkeys only

### Requirement: User CA private key SHALL NOT be deployed to gateway
SSH PAM deployment artifacts SHALL NOT include or copy the User CA private key to gateway host, container, or git repository.

#### Scenario: Only public CA in repository
- **WHEN** QA enables CA trust
- **THEN** only `*.pub` CA material MAY be stored in `lab/ca/` or supplied from secure controller path
- **THEN** private CA key paths SHALL remain outside the bastion deployment tree
