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

### Requirement: Audit role SHALL execute only structured read-only commands

The audit shell SHALL parse input into a validated argv vector and invoke an
absolute allowlisted executable directly. It SHALL NOT execute the original
input through `eval`, `sh -c`, shell expansion or equivalent evaluation.

#### Scenario: Allowed read-only command
- **WHEN** an audit operator submits an allowed command with valid options and
  canonical paths under `audit_log_dir`
- **THEN** the command SHALL execute as an argv vector without a shell
- **AND** the allow event SHALL identify operator, executable and canonical
  resource scope

#### Scenario: Command substitution
- **WHEN** input contains `$()`, backticks, variable expansion or process
  substitution
- **THEN** the request SHALL be denied before any expansion occurs
- **AND** no side-effect command SHALL execute

#### Scenario: Shell control syntax
- **WHEN** input contains pipeline, redirection, semicolon, background,
  conditional operator, embedded newline or NUL
- **THEN** the complete request SHALL be denied
- **AND** no partial command SHALL execute

#### Scenario: Path traversal or symlink escape
- **WHEN** a path resolves outside `audit_log_dir`
- **THEN** access SHALL be denied even if the lexical path begins under the
  allowed directory

#### Scenario: Unsafe utility option
- **WHEN** an allowed executable receives an option capable of writing files,
  launching a shell or executing another program
- **THEN** the option SHALL be denied unless a command-specific policy
  explicitly proves it read-only

### Requirement: Audit denial SHALL be observable

The gateway SHALL record structured evidence for every audit-role policy
denial without executing the rejected input.

#### Scenario: Policy denial
- **WHEN** an audit command is rejected
- **THEN** the gateway SHALL emit structured telemetry containing operator,
  reason and command identifier
- **AND** telemetry SHALL NOT expose secrets or unbounded attacker-controlled
  content
