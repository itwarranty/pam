### Requirement: Gateway lifecycle events SHALL be exportable as structured records

SSH PAM SHALL append machine-readable session events for client SIEM indexing.

#### Scenario: Gateway session start
- **WHEN** gateway session starts
- **THEN** a JSON line SHALL be appended to `{{ audit_log_dir }}/sessions.jsonl`
- **THEN** record SHALL include at minimum: `event`, `ts`, `operator`, `target_id`, `target_host`, `session_id`, `client`, `incident_id` (if set)

#### Scenario: Gateway session end
- **WHEN** gateway session ends
- **THEN** a JSON line with `event=gateway_end` SHALL be appended
- **THEN** record SHALL include `exit_code` and `log_sha256` when available

### Requirement: Structured export SHALL not replace syslog or file logs

#### Scenario: SIEM integration
- **WHEN** client uses only rsyslog (Tier 1)
- **THEN** gateway deployment SHALL remain functional without JSONL consumer
- **THEN** design appendix SHALL document optional `imfile` ingestion of `sessions.jsonl`

### Requirement: JSONL files SHALL be protected like session logs

#### Scenario: Permissions
- **WHEN** `sessions.jsonl` is created
- **THEN** file SHALL be owned by `pam_user` with mode `0640` or tighter
- **THEN** directory `audit_log_dir` permissions SHALL remain `0750`

### Requirement: Search workflow SHALL be documented for auditors

#### Scenario: Auditor without SIEM
- **WHEN** auditor needs commands for target on date D
- **THEN** Troubleshooting Workflow SHALL document `grep` on gateway logs and optional `jq` on JSONL
