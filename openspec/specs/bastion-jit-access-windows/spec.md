## ADDED Requirements

### Requirement: Operators MAY declare time-bound access windows

MT: Bastion Free SHALL support optional Just-in-Time fields on each entry in `bastion_operators`.

#### Scenario: Operator schema extension
- **WHEN** administrator defines an operator
- **THEN** the following optional fields MAY be set:
  - `valid_from` — ISO8601 timestamp with timezone
  - `valid_until` — ISO8601 timestamp with timezone
  - `incident_id` — string correlating to ITSM ticket (e.g. `INC-2026-8942`)

### Requirement: Expired operators SHALL be removed declaratively on playbook run

When an operator's `valid_until` is in the past, MT: Bastion SHALL treat that operator as revoked and execute purge semantics.

#### Scenario: Expired operator purged on deploy
- **WHEN** `ansible-playbook site.yml` runs
- **AND** operator `engineer1` has `valid_until` earlier than current time on bastion host
- **THEN** `engineer1` SHALL NOT appear in effective provisioned operators
- **THEN** `purge_revoked_operators.yml` semantics SHALL remove host directory, MFA onboarding file, and container Unix account
- **THEN** handler SHALL restart `mt_ssh_bastion` if purge occurred

#### Scenario: Future valid_from operator not yet active
- **WHEN** operator has `valid_from` in the future
- **THEN** v1 implementation MAY provision keys but SHOULD document that purge-only defers access until window starts (live sshd rejection is Phase B optional enhancement)

### Requirement: JIT expiry SHALL be automatable without manual Ansible operator

MT: Bastion Free SHALL document and optionally ship a host timer to re-apply playbook for JIT purge.

#### Scenario: systemd timer template
- **WHEN** `bastion_jit_timer_enabled: true`
- **THEN** Ansible SHALL install a systemd timer on bastion host that runs playbook or a wrapper with tag `jit_purge` on configurable interval (default: hourly)
- **THEN** timer SHALL run as root with sudo to invoke ansible-pull OR client-supplied script path `bastion_jit_playbook_command`

#### Scenario: Manual JIT close still supported
- **WHEN** administrator removes operator from `bastion_operators` manually
- **THEN** existing purge flow SHALL apply without requiring `valid_until`

### Requirement: JIT metadata SHALL appear in audit artifacts when incident_id is set

Session audit trail SHOULD correlate to ITSM ticket when provided.

#### Scenario: Incident ID in session log metadata
- **WHEN** operator has `incident_id` set
- **AND** operator starts shell session (access shell)
- **THEN** tamper-evident log sidecar (see `bastion-tamper-evident-session-logs`) SHALL include `INCIDENT=<incident_id>` when Tier 1 logging is implemented
