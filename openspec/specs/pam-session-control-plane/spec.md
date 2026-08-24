### Requirement: Active gateway sessions SHALL be observable

SSH PAM SHALL expose active gateway sessions to client CSO without proprietary UI.

#### Scenario: List sessions
- **WHEN** client runs `pam-session-ctl list` on the gateway host (documented path)
- **THEN** output SHALL include session id, operator name, target id/host, start time, and PID or container reference

#### Scenario: No active sessions
- **WHEN** no gateway session is running
- **THEN** list command SHALL exit 0 with empty or explicit "no sessions" message

### Requirement: Client CSO SHALL be able to terminate gateway sessions

#### Scenario: Kill by session id
- **WHEN** CSO runs `pam-session-ctl kill <session-id>`
- **THEN** the corresponding gateway session SHALL terminate within documented timeout (default 10s)
- **THEN** session registry entry SHALL be removed
- **THEN** syslog event `pam-session-kill` SHALL be emitted

#### Scenario: Kill by operator
- **WHEN** CSO runs `pam-session-ctl kill --operator <name>`
- **THEN** all active gateway sessions for that operator SHALL be terminated

### Requirement: JIT purge SHALL terminate active sessions for revoked operators

#### Scenario: Operator JIT expired during active gateway session
- **WHEN** `jit_purge` runs and operator is expired or removed from effective list
- **AND** operator has active gateway session
- **THEN** purge workflow SHALL kill active sessions before or during container restart handler

### Requirement: Ansible SHALL expose session kill tag

#### Scenario: Remote kill via Ansible
- **WHEN** playbook runs with tag `session_kill` and `pam_session_kill_id` set
- **THEN** specified session SHALL be terminated without full redeploy

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
