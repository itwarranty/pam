### Requirement: SSH PAM SHALL support active-passive HA pattern

SSH PAM SHALL document and automate baseline two-node HA for session log continuity.

#### Scenario: Primary and standby inventory
- **WHEN** inventory defines `pam_primary` and `pam_standby` groups
- **THEN** Ansible SHALL deploy full stack on primary
- **THEN** standby SHALL receive synchronized configuration and image
- **THEN** standby container MAY remain stopped until promotion (documented default)

#### Scenario: Shared session log storage
- **WHEN** `pam_ha_enabled: true`
- **THEN** `audit_log_dir` SHALL be mounted from shared NFS/WORM path documented in `pam_ha_shared_log_mount`
- **THEN** both nodes SHALL use same path for `sessions.jsonl` and gateway logs

### Requirement: Failover procedure SHALL be documented

#### Scenario: Primary failure
- **WHEN** operator follows `docs/HA-Runbook.md`
- **THEN** runbook SHALL describe VIP/DNS update, `pam-ha-promote.sh`, container start on standby
- **THEN** runbook SHALL state active sessions on primary are lost

### Requirement: Split-brain SHALL be prevented by operational rules

#### Scenario: Documentation
- **WHEN** HA enabled
- **THEN** docs SHALL require either manual promotion OR external STONITH — not dual-primary

### Requirement: Session registry SHALL NOT be replicated in v1

#### Scenario: Failover during active session
- **WHEN** failover occurs
- **THEN** session registry on primary is stale; documentation SHALL instruct kill or wait for natural end

### Requirement: HA SHALL remain SSH-only

#### Scenario: Scope
- **WHEN** HA deploy completes
- **THEN** no multi-protocol components SHALL be introduced
