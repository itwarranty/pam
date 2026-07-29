### Requirement: Session log filenames SHALL include incident_id when configured

When an operator has `incident_id`, SSH PAM SHALL embed a sanitized ticket reference in the session log basename.

#### Scenario: Operator with incident_id starts shell session
- **WHEN** operator has non-empty `incident_id`
- **AND** `sshd_config` sets `PAM_INCIDENT_ID` for that user
- **THEN** `pam-shell-wrapper.sh` SHALL create log file matching pattern `session_<SANITIZED_INCIDENT>_<USER>_<YYYYMMDD>_<HHMMSS>.log`

#### Scenario: Operator without incident_id
- **WHEN** `incident_id` is absent or empty
- **THEN** log filename SHALL remain `session_<USER>_<YYYYMMDD>_<HHMMSS>.log` (Tier 1 behavior)

#### Scenario: Incident id sanitization
- **WHEN** `incident_id` contains characters outside `[A-Za-z0-9._-]`
- **THEN** wrapper SHALL strip or replace invalid characters before use in filename
- **THEN** sanitized segment SHALL be truncated to 64 characters maximum

### Requirement: Sidecar integrity artifacts SHALL follow log basename

Tamper-evident sidecars SHALL remain adjacent to the session log file.

#### Scenario: Session ends with incident in filename
- **WHEN** shell session terminates
- **THEN** `.sha256` and `.meta` sidecars SHALL use the same basename as the session log
- **AND** `.meta` SHALL still include `INCIDENT=` field (Tier 1)

### Requirement: Container image rebuild SHALL be documented after wrapper change

Filename logic lives in immutable container image.

#### Scenario: Engineer deploys Tier 2 Phase A
- **WHEN** incident log naming is implemented in `build/files/pam-shell-wrapper.sh`
- **THEN** Engineer Onboarding and CSO Demo Runbook SHALL instruct `./trusted_download.sh` + image reload before verify
