### Requirement: Gateway sessions SHALL be recorded on bastion host

MT: Bastion SHALL capture the full interactive PTY stream for `access: gateway` sessions to target systems.

#### Scenario: Successful gateway session
- **WHEN** operator completes gateway session to target
- **THEN** a log file SHALL exist under `audit_log_dir` (default `/var/log/bastion_sessions`)
- **THEN** log basename SHALL match pattern `gateway_<SANITIZED_INCIDENT>_<OPERATOR>_<TARGETID>_<YYYYMMDD>_<HHMMSS>.log` when `incident_id` is set
- **THEN** log basename SHALL match `gateway_<OPERATOR>_<TARGETID>_<YYYYMMDD>_<HHMMSS>.log` when `incident_id` is absent

#### Scenario: Tamper-evident sidecars
- **WHEN** gateway session ends
- **THEN** `.sha256` and `.meta` sidecars SHALL be written adjacent to the log file
- **THEN** `.meta` SHALL include `MODE=gateway`, `TARGET=`, `TARGET_HOST=`, `TARGET_ACCOUNT=`

#### Scenario: Append-only protection
- **WHEN** gateway log file is created
- **THEN** `chattr +a` SHALL be applied to log and sidecars (same as shell wrapper)

### Requirement: Gateway recording SHALL NOT rely on target-side agents

Recording SHALL occur entirely on bastion host.

#### Scenario: Target has stock OpenSSH server only
- **WHEN** target runs standard `sshd` without MT Bastion agent
- **THEN** gateway recording SHALL still produce full session log on bastion

### Requirement: Container image rebuild SHALL be required after recording changes

#### Scenario: Engineer deploys Tier 3 Phase A
- **WHEN** gateway wrappers change in `build/files/`
- **THEN** documentation SHALL require `./trusted_download.sh` and image reload before verification
