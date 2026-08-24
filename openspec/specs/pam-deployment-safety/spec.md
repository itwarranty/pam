### Requirement: Unchanged deployment SHALL be idempotent

Repeated deployment with identical effective inputs SHALL not mutate
authentication material or disrupt the running gateway.

#### Scenario: Second identical playbook run
- **WHEN** inventory, image and configuration are unchanged
- **THEN** the SSH PAM container SHALL NOT restart or recreate
- **AND** MFA secrets SHALL NOT change
- **AND** no SELinux task SHALL report a false change

#### Scenario: Effective runtime change
- **WHEN** image, mounts, ports, environment or effective SSH configuration
  changes
- **THEN** the container SHALL converge with at most one planned disruptive
  action

### Requirement: Deployment SHALL protect active sessions

SSH PAM deployment SHALL detect and protect active sessions before any
disruptive container action.

#### Scenario: Active sessions and no override
- **WHEN** a deployment requires container restart/recreate
- **AND** active gateway sessions exist
- **AND** disruptive override is false
- **THEN** deployment SHALL fail before interruption with actionable session
  details

#### Scenario: Explicit disruptive override
- **WHEN** an authorized operator explicitly enables disruption
- **THEN** deployment MAY continue
- **AND** affected sessions and the override SHALL be audited

### Requirement: Operational commands SHALL honor configured identities

All deployment, control and verification operations SHALL use effective PAM
variables instead of hard-coded runtime names.

#### Scenario: Non-default container name
- **WHEN** `pam_container_name` differs from `ssh_pam`
- **THEN** deploy, handlers, control scripts and compliance SHALL operate on the
  configured name

#### Scenario: Non-default PAM paths
- **WHEN** PAM user/home/runtime/audit paths are overridden
- **THEN** operational tasks SHALL derive paths from configuration
- **AND** SHALL NOT fall back to removed gateway/bastion paths

### Requirement: SELinux convergence SHALL be declarative

SELinux labeling SHALL converge without reporting false changes or triggering
unnecessary container restarts.

#### Scenario: Correct label already present
- **WHEN** a managed path already has the expected SELinux context
- **THEN** the task SHALL report unchanged
- **AND** SHALL NOT notify container restart
