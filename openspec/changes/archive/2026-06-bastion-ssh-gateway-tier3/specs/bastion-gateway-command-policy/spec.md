### Requirement: Gateway sessions SHALL enforce command denylist when policy enabled

When `bastion_shell_command_policy_enabled` is `true`, gateway PTY SHALL apply the same denylist as shell sessions.

#### Scenario: Denied command on target via gateway
- **WHEN** operator types interactive command matching denylist regex
- **THEN** command SHALL NOT be executed on target
- **THEN** denial SHALL be logged via syslog tag `mt-bastion-deny`
- **THEN** log metadata SHALL include `MODE=gateway`

#### Scenario: Policy disabled
- **WHEN** `bastion_shell_command_policy_enabled` is `false`
- **THEN** gateway sessions SHALL record commands without deny enforcement

### Requirement: Gateway command policy limitations SHALL be documented

#### Scenario: CSO security review
- **WHEN** documentation describes gateway command policy
- **THEN** it SHALL state best-effort interactive filtering (same class of limitations as shell denylist)
- **THEN** it SHALL recommend least-privilege target account and sudo logging on target

### Requirement: Denylist source SHALL remain declarative

#### Scenario: Deploy
- **WHEN** command policy enabled
- **THEN** gateway SHALL read `/etc/bastion/command_denylist` (existing Tier 2 mount)
