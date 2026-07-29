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
  - `ssh_pam` container is running under user `gateway`
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
- **THEN** it SHALL assert `/var/log/pam_sessions` (or `audit_log_dir`) exists with owner `gateway` and mode `0750`

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
