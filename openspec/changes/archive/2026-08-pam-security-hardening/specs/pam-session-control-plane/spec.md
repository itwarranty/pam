## MODIFIED Requirements

### Requirement: Session registry SHALL identify the complete process group

Each active gateway registry record SHALL identify a validated process group
representing the complete local session chain.

#### Scenario: Gateway session starts
- **WHEN** a gateway target session is created
- **THEN** its registry record SHALL include schema version, PID and PGID
- **AND** the gateway process chain SHALL run in a dedicated process group

#### Scenario: Registry validation
- **WHEN** a control command reads a session record
- **THEN** it SHALL validate record ownership, session id, numeric PID/PGID,
  effective UID and expected process ancestry before signaling

### Requirement: Session kill SHALL terminate the complete gateway process tree

An authorized session kill SHALL terminate and verify the complete gateway
process group rather than only one wrapper PID.

#### Scenario: Graceful termination
- **WHEN** an authorized operator kills an active session
- **THEN** the control plane SHALL send SIGTERM to the validated process group
- **AND** wait up to the configured timeout
- **AND** verify that wrapper, recorder, inspector and nested SSH processes have
  exited

#### Scenario: Forced termination
- **WHEN** processes remain after the graceful timeout
- **THEN** the control plane MAY send SIGKILL to the same validated process
  group according to policy
- **AND** SHALL report whether any process survived

#### Scenario: Target channel
- **WHEN** local session kill completes successfully
- **THEN** the SSH channel to the target SHALL be closed

#### Scenario: Audit events
- **WHEN** kill starts or completes
- **THEN** structured events SHALL include actor, session id, operator, target,
  PGID and outcome

### Requirement: Registry schema migration SHALL be bounded

PID-only legacy registry records SHALL be supported only through an explicit,
safe compatibility path during a documented migration window.

#### Scenario: Legacy schema record
- **WHEN** a schema 1 PID-only record is encountered during the compatibility
  window
- **THEN** the tool SHALL warn and use a safe descendant validation fallback
- **AND** SHALL NOT signal an unvalidated reused PID
