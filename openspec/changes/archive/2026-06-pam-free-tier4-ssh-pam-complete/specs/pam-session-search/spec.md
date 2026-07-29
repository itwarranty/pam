### Requirement: SSH PAM SHALL provide session search without external database

SSH PAM operators and auditors SHALL query historical sessions from host-local artifacts.

#### Scenario: Search by operator and time window
- **WHEN** user runs `pam-session-search --operator engineer1 --since 7d`
- **THEN** command SHALL list matching sessions from `sessions.jsonl` with session_id, target_id, target_host, started_at, ended_at (if known), log_path
- **THEN** exit code SHALL be 0 when matches exist, 0 when empty (with message), non-zero only on error

#### Scenario: JSON output for automation
- **WHEN** `--json` flag is passed
- **THEN** output SHALL be valid JSON array of session records

#### Scenario: Search by incident id
- **WHEN** `--incident INC-2026-8942` is passed
- **THEN** all gateway_start/end records with matching incident_id SHALL be returned

### Requirement: Optional grep inside session logs

Full-text command search MAY be supported with explicit slow path.

#### Scenario: Grep mode
- **WHEN** `--grep 'rm -rf'` is passed
- **THEN** tool SHALL search gateway/shell `.log` files under audit_log_dir matching prior JSONL filter or global date window
- **THEN** documentation SHALL warn about performance on large archives

### Requirement: Session search SHALL respect log directory permissions

#### Scenario: Non-root auditor
- **WHEN** auditor lacks read access to audit_log_dir
- **THEN** command SHALL fail with permission error (document sudo/runuser for audit role)

### Requirement: jq dependency SHALL be documented

#### Scenario: Rocky Linux 9 deploy with search enabled
- **WHEN** `pam_session_search_enabled: true`
- **THEN** playbook or docs SHALL ensure `jq` package on the gateway host
