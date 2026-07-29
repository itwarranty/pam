### Requirement: Break-glass operators SHALL require explicit CSO gate and mandatory metadata

SSH PAM SHALL treat break-glass as an opt-in emergency profile controlled by Ansible variables and operator fields.

#### Scenario: Break-glass disabled in prod
- **WHEN** `pam_break_glass_enabled` is `false` (default)
- **AND** an operator entry has `break_glass: true`
- **THEN** preflight SHALL fail with operator name and remediation message

#### Scenario: Break-glass enabled with valid metadata
- **WHEN** `pam_break_glass_enabled` is `true`
- **AND** operator has `break_glass: true`, non-empty `incident_id`, and `valid_until`
- **AND** window duration is ≤ `pam_break_glass_max_hours`
- **THEN** preflight SHALL pass
- **THEN** operator SHALL be provisioned like other operators with enhanced audit markers

#### Scenario: Break-glass missing incident_id
- **WHEN** operator has `break_glass: true`
- **AND** `incident_id` is empty or absent
- **THEN** preflight SHALL fail

#### Scenario: Break-glass window exceeds maximum
- **WHEN** operator has `break_glass: true`
- **AND** `valid_until - valid_from` (or `valid_until - now` if `valid_from` absent) exceeds `pam_break_glass_max_hours`
- **THEN** preflight SHALL fail

### Requirement: Break-glass sessions SHALL emit enhanced audit signals

Emergency sessions SHALL be distinguishable in host and SIEM logs.

#### Scenario: Break-glass shell session starts
- **WHEN** operator with `break_glass: true` starts `access: shell` session
- **THEN** session start event SHALL include `BREAK_GLASS=1` in syslog message
- **AND** auditd rule key `pam_break_glass_session` SHALL fire on session log write (when audit rules deployed)

### Requirement: Break-glass access SHALL auto-expire via JIT purge

Break-glass SHALL NOT outlive its declared window without manual YAML cleanup.

#### Scenario: valid_until in the past
- **WHEN** break-glass operator `valid_until` is before current gateway host time
- **AND** playbook runs (or `--tags jit_purge`)
- **THEN** operator SHALL be purged per `gateway-jit-access-windows` semantics
