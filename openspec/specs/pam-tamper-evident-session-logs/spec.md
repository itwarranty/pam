## ADDED Requirements

### Requirement: Shell session logs SHALL receive cryptographic integrity sidecar at session end

SSH PAM SHALL produce verifiable hashes for TTY session recordings.

#### Scenario: SHA256 sidecar created on session close
- **WHEN** shell operator session ends (access shell via `pam-shell-wrapper.sh`)
- **THEN** a file named `<session_log_path>.sha256` SHALL be written alongside the log
- **THEN** sidecar SHALL contain SHA256 hex digest of the log file at close time

#### Scenario: Sidecar format is machine-parseable
- **WHEN** sidecar is written
- **THEN** it SHALL include at minimum: `SHA256=`, `UTC=` (ISO8601), `USER=`
- **AND** MAY include `INCIDENT=` when incident metadata is available
- **AND** MAY include `CLIENT=` from `SSH_CLIENT`

### Requirement: Append-only attribute SHALL remain applied at log creation

Existing at-birth protection SHALL NOT be regressed.

#### Scenario: chattr +a on log file
- **WHEN** session log file is created
- **THEN** `chattr +a` SHALL be applied before substantial content is written (existing wrapper behavior)

### Requirement: CSO SHALL be able to verify log integrity before ticket attachment

Documentation and tooling SHALL support independent hash verification.

#### Scenario: Manual verification command
- **WHEN** auditor runs `sha256sum -c session_*.log.sha256` on the gateway host
- **THEN** verification SHALL succeed if log was not modified since sidecar creation

#### Scenario: Append-only prevents operator deletion
- **WHEN** compromised operator attempts truncate/delete of active log
- **THEN** append-only attribute SHALL prevent removal or overwrite of existing content (audit-safe: not absolute against root on host — document host root custody)

### Requirement: Optional WORM archive path MAY copy closed logs to client storage

Air Gap customers with WORM NAS MAY enable archival.

#### Scenario: WORM archive disabled
- **WHEN** `pam_worm_archive_dir` is empty
- **THEN** no archive task SHALL run

#### Scenario: WORM archive enabled
- **WHEN** `pam_worm_archive_dir` is set to writable-only-by-automation mount
- **THEN** Ansible task or documented cron MAY copy `*.log` and `*.sha256` pairs where log file is not open (mtime stable > N minutes)

### Requirement: Tamper-evident logging SHALL NOT replace SIEM forwarding

Hash sidecars complement — not replace — syslog/auditd pipeline in `pam-siem-syslog-export`.

#### Scenario: Both controls active
- **WHEN** SIEM forward and tamper-evident logs are enabled
- **THEN** auditd SHALL continue to record writes to session log directory
- **AND** sidecar files SHALL be included in integrity checks
