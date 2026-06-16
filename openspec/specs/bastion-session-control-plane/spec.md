### Requirement: Active gateway sessions SHALL be observable

MT: Bastion SHALL expose active gateway sessions to client CSO without proprietary UI.

#### Scenario: List sessions
- **WHEN** client runs `bastion-session-ctl list` on bastion host (documented path)
- **THEN** output SHALL include session id, operator name, target id/host, start time, and PID or container reference

#### Scenario: No active sessions
- **WHEN** no gateway session is running
- **THEN** list command SHALL exit 0 with empty or explicit "no sessions" message

### Requirement: Client CSO SHALL be able to terminate gateway sessions

#### Scenario: Kill by session id
- **WHEN** CSO runs `bastion-session-ctl kill <session-id>`
- **THEN** the corresponding gateway session SHALL terminate within documented timeout (default 10s)
- **THEN** session registry entry SHALL be removed
- **THEN** syslog event `mt-bastion-session-kill` SHALL be emitted

#### Scenario: Kill by operator
- **WHEN** CSO runs `bastion-session-ctl kill --operator <name>`
- **THEN** all active gateway sessions for that operator SHALL be terminated

### Requirement: JIT purge SHALL terminate active sessions for revoked operators

#### Scenario: Operator JIT expired during active gateway session
- **WHEN** `jit_purge` runs and operator is expired or removed from effective list
- **AND** operator has active gateway session
- **THEN** purge workflow SHALL kill active sessions before or during container restart handler

### Requirement: Ansible SHALL expose session kill tag

#### Scenario: Remote kill via Ansible
- **WHEN** playbook runs with tag `session_kill` and `bastion_session_kill_id` set
- **THEN** specified session SHALL be terminated without full redeploy
