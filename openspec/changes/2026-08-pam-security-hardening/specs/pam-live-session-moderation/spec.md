## MODIFIED Requirements

### Requirement: Live watch SHALL enforce moderator authorization

Live session list/watch operations SHALL authorize the caller before exposing
session metadata or log content.

#### Scenario: Root watches a session
- **WHEN** effective UID is root and the session record is valid
- **THEN** read-only watch SHALL be permitted

#### Scenario: Moderator group watches a session
- **WHEN** the caller belongs to configured `pam_moderators_group`
- **THEN** read-only watch SHALL be permitted

#### Scenario: Unauthorized host user
- **WHEN** a caller is neither root nor an authorized moderator/audit identity
- **THEN** list/watch SHALL exit non-zero before opening the log
- **AND** a denied moderation event SHALL be emitted

### Requirement: Live watch SHALL resolve only trusted paths

Live watch SHALL open only canonical session-log paths rooted under the
configured audit directory.

#### Scenario: Valid registry log path
- **WHEN** a validated active-session registry points to a canonical file under
  `audit_log_dir`
- **THEN** the script MAY tail the file read-only

#### Scenario: Traversal or symlink escape
- **WHEN** registry `log_path` resolves outside `audit_log_dir`
- **THEN** watch SHALL fail closed
- **AND** SHALL NOT read the referenced file

### Requirement: Runtime paths SHALL derive from PAM configuration

Session moderation SHALL derive registry and audit paths from effective PAM
configuration.

#### Scenario: No environment override
- **WHEN** `PAM_RUNTIME_SESSIONS_DIR` is unset
- **THEN** the default SHALL resolve to the configured PAM runtime directory
- **AND** SHALL NOT use removed `/home/gateway` naming

### Requirement: Moderation attempts SHALL be audited

Successful and denied moderation attempts SHALL produce structured audit
telemetry.

#### Scenario: Watch allow or deny
- **WHEN** a watch attempt occurs
- **THEN** telemetry SHALL record actor, session id, source, outcome and reason
- **AND** the action SHALL remain read-only (no PTY input injection)
