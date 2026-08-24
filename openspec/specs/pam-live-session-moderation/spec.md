### Requirement: Client moderators SHALL observe active gateway sessions read-only

SSH PAM SHALL support four-eyes oversight without write access to target.

#### Scenario: Watch active session
- **WHEN** user with `access: audit` runs `pam-session-watch <session-id>` on the gateway host
- **THEN** tool SHALL tail -f the active session log file referenced in session registry
- **THEN** moderator SHALL NOT write to operator PTY

#### Scenario: List watchable sessions
- **WHEN** `pam-session-watch --list` is run
- **THEN** output SHALL match active sessions from session registry (same as session-ctl list)

### Requirement: Moderator attach SHALL be audited

#### Scenario: Watch starts
- **WHEN** moderator starts watch
- **THEN** JSONL event `moderator_watch_start` SHALL be appended with moderator identity and session_id
- **THEN** syslog event SHALL be emitted

### Requirement: Only root or configured moderators MAY watch

#### Scenario: Root watches a session
- **WHEN** effective UID is root and the session record is valid
- **THEN** read-only watch SHALL be permitted

#### Scenario: Moderator group watches a session
- **WHEN** the caller belongs to configured `pam_moderators_group`
- **THEN** read-only watch SHALL be permitted

#### Scenario: Unauthorized host user
- **WHEN** a caller is neither root nor an authorized moderator identity
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

### Requirement: Live watch SHALL use gateway-recorded stream

#### Scenario: Documentation
- **WHEN** CSO reads moderation section
- **THEN** docs SHALL state watch uses recorded PTY stream (near-real-time), not separate video protocol
