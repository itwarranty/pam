## ADDED Requirements

### Requirement: SSH PAM SHALL provide automated compliance verification

A verify command SHALL confirm gateway host state matches CSO Policy Gate expectations.

#### Scenario: Compliance script exists
- **WHEN** repository is deployed
- **THEN** `scripts/pam-compliance-verify.sh` SHALL be present and executable

#### Scenario: Script exit code indicates pass/fail
- **WHEN** all checks pass on a correctly deployed Rocky 9 gateway
- **THEN** script SHALL exit `0`
- **WHEN** any critical check fails
- **THEN** script SHALL exit non-zero and print failing check names

### Requirement: Compliance verify SHALL include minimum CSO checks

Verification coverage SHALL match Policy Gate decisions.

#### Scenario: Platform checks
- **WHEN** verify runs on the gateway host
- **THEN** it SHALL assert:
  - distribution is Rocky Linux 9.x
  - architecture is x86_64
  - SELinux mode is Enforcing

#### Scenario: Runtime checks
- **WHEN** verify runs
- **THEN** it SHALL assert:
  - `pam_container_name` container is running under user `pam`
  - loaded image label `pam.mfa.strict` equals `1`
  - `auditd` is active
  - `firewalld` is active

#### Scenario: Policy checks
- **WHEN** verify runs with access to deployed config
- **THEN** it SHALL assert:
  - `pam_permitted_targets` is non-empty (from host-side deployed sshd_config or ansible vars file if present)
  - no orphan Unix users in container `/home` outside configured operator list (best-effort via `podman exec`)

#### Scenario: Session log directory checks
- **WHEN** verify runs
- **THEN** it SHALL assert `audit_log_dir` exists with owner `pam` and mode `0750`
- **AND** aggregate files such as `gateway.syslog` SHALL NOT be world-writable in production

#### Scenario: Command policy v2 checks
- **WHEN** `pam_command_policy_v2_required` is `true`
- **AND** `pam_shell_command_policy_enabled` is `true`
- **THEN** verify SHALL assert container has `/run/ssh-pam/policy_v2_enabled` and `/run/ssh-pam/shell_policy_v2_enabled`
- **THEN** verify SHALL assert `pam-pty-inspector.py` exists in image

### Requirement: Ansible SHALL expose equivalent verify via tag

Remote verification SHALL be available without SSH login to run script manually.

#### Scenario: Ansible tag verify_compliance
- **WHEN** administrator runs `ansible-playbook site.yml --tags verify_compliance`
- **THEN** `tasks/verify_compliance_cso.yml` SHALL execute the same logical checks
- **THEN** playbook SHALL fail if any check fails

### Requirement: Compliance verify SHALL be suitable for CSO demo and periodic audit

Output SHALL be human-readable for presales and auditors.

#### Scenario: Demo-friendly output
- **WHEN** verify script runs successfully
- **THEN** stdout SHALL list passed checks in concise form suitable for CSO demo screen share

#### Scenario: CI syntax does not replace compliance verify
- **WHEN** GitHub Actions runs syntax-check only
- **THEN** full compliance verify remains a post-deploy manual/scheduled step on Rocky 9 host (CI cannot replace without Lima integration — optional future)

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
