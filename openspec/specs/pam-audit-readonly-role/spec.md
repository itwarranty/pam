### Requirement: Operators SHALL support access mode audit

SSH PAM SHALL allow a read-only auditor role for reviewing session artifacts without target access.

#### Scenario: Audit operator provisioned
- **WHEN** operator entry has `access: audit`
- **THEN** `authorized_keys` SHALL NOT include `restrict,port-forwarding` (PTY required)
- **THEN** `sshd_config` Match block SHALL set `ForceCommand /usr/local/bin/pam-audit-shell-wrapper.sh`
- **THEN** `AllowTcpForwarding` SHALL be `no` for that user

#### Scenario: Audit operator attempts ProxyJump
- **WHEN** auditor connects with `-J` or port forwarding
- **THEN** TCP forwarding SHALL be denied by sshd configuration

### Requirement: Audit shell SHALL restrict filesystem access to session log directory

Auditors SHALL read logs only under the configured audit directory.

#### Scenario: Allowed read
- **WHEN** audit operator runs `less`, `cat`, `ls`, `head`, `grep`, or `sha256sum` on path under `/var/log/pam_sessions`
- **THEN** command SHALL succeed (read-only)

#### Scenario: Path outside audit directory
- **WHEN** audit operator attempts to read `/etc/passwd` or use `..` traversal outside audit dir
- **THEN** wrapper SHALL deny command and log denial

#### Scenario: Write attempt
- **WHEN** audit operator attempts redirect, `rm`, `touch`, or `chattr` on any path
- **THEN** wrapper SHALL deny command

### Requirement: Audit sessions SHALL be recorded

Auditor activity itself SHALL be auditable.

#### Scenario: Audit session lifecycle
- **WHEN** audit operator connects
- **THEN** `pam-audit-shell-wrapper.sh` SHALL record session via `script` with tamper-evident sidecars (same pattern as shell wrapper)
- **THEN** log filename SHALL use prefix `audit_session_` to distinguish from support shell logs

### Requirement: Preflight SHALL validate access enum

Only declared access modes are permitted.

#### Scenario: Invalid access value
- **WHEN** operator `access` is not one of `jump`, `shell`, `audit`
- **THEN** preflight SHALL fail

#### Scenario: Audit role in commercial PAM branch
- **WHEN** `is_commercial_pam` is `true`
- **AND** operator has `access: audit`
- **THEN** preflight SHALL fail until commercial PAM spec defines auditor integration
