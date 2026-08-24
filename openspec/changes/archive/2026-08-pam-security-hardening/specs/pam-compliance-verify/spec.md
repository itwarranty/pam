## MODIFIED Requirements

### Requirement: Compliance SHALL verify configured runtime identities

Compliance checks SHALL derive container, user and filesystem identities from
the effective PAM configuration.

#### Scenario: Custom container name
- **WHEN** `pam_container_name` differs from the default
- **THEN** Ansible and CLI compliance SHALL inspect the configured container
- **AND** SHALL return equivalent results

#### Scenario: Custom PAM paths
- **WHEN** user, home, runtime or audit paths are configured
- **THEN** compliance SHALL derive checks from those values
- **AND** SHALL NOT use removed gateway/bastion defaults

### Requirement: Compliance SHALL verify hardening controls

Compliance SHALL verify that each enabled security-hardening control is both
configured and active in the deployed runtime.

#### Scenario: Audit executor
- **WHEN** audit role is enabled
- **THEN** compliance SHALL verify the structured executor is installed
- **AND** SHALL reject a known shell-evaluation implementation marker

#### Scenario: Command policy v2
- **WHEN** policy v2 is required
- **THEN** compliance SHALL verify its runtime marker and complete-line gate
  build/version

#### Scenario: Session control
- **WHEN** gateway sessions are enabled
- **THEN** compliance SHALL verify registry schema v2 support and process-group
  kill tooling

#### Scenario: MFA lifecycle
- **WHEN** production profile is selected
- **THEN** compliance/preflight SHALL verify silent bootstrap generation is
  disabled

#### Scenario: Moderation authorization
- **WHEN** live watch is enabled
- **THEN** compliance SHALL verify an authorization policy/group is configured
  and the registry path matches PAM runtime configuration

#### Scenario: Audit log permissions
- **WHEN** production profile is selected
- **THEN** compliance SHALL fail if aggregate audit files are world-writable

### Requirement: CLI and Ansible compliance SHALL remain equivalent

The host CLI and Ansible verification path SHALL express equivalent control
semantics and outcomes.

#### Scenario: Same deployed host
- **WHEN** `pam verify --json` and Ansible `verify_compliance` run against the
  same effective configuration
- **THEN** enabled controls SHALL produce the same pass/fail outcome
- **AND** machine-readable output SHALL identify failed control ids
