## MODIFIED Requirements

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
