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

### Requirement: Only audit role or documented sudo group MAY watch

#### Scenario: Unauthorized user
- **WHEN** user without audit SSH account or `pam_moderators` sudo group attempts watch
- **THEN** command SHALL refuse with non-zero exit

### Requirement: Live watch SHALL use gateway-recorded stream

#### Scenario: Documentation
- **WHEN** CSO reads moderation section
- **THEN** docs SHALL state watch uses recorded PTY stream (near-real-time), not separate video protocol
