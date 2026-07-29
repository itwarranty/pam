### Requirement: Shell role SHALL enforce configurable command denylist

When command policy is enabled, SSH PAM SHALL block dangerous interactive commands for `access: shell` operators.

#### Scenario: Policy enabled with default denylist
- **WHEN** `pam_shell_command_policy_enabled` is `true`
- **AND** operator has `access: shell`
- **THEN** `pam-shell-wrapper.sh` SHALL load denylist from container path `/etc/ssh-pam/command_denylist`
- **THEN** jump operators (`access: jump`) SHALL NOT be affected

#### Scenario: Denied command entered
- **WHEN** shell operator attempts a command matching a denylist regex
- **THEN** command SHALL NOT execute
- **THEN** denial SHALL be logged via syslog tag `pam-deny`
- **AND** operator SHALL receive a clear denial message referencing CSO policy

#### Scenario: Policy disabled
- **WHEN** `pam_shell_command_policy_enabled` is `false`
- **THEN** shell wrapper behavior SHALL match pre-Tier-2 (record session only)

### Requirement: Denylist SHALL be declarative in Ansible

Operators SHALL NOT edit denylist inside running container by default.

#### Scenario: Playbook deploy
- **WHEN** `pam_shell_command_policy_enabled` is `true`
- **THEN** Ansible SHALL render denylist file on the gateway host and mount read-only into container at `/etc/ssh-pam/command_denylist`
- **THEN** default denylist SHALL include at minimum patterns for `rm -rf /` and `iptables -F`

### Requirement: Command policy limitations SHALL be documented

SSH PAM SHALL document that denylist is best-effort for interactive bash, not a kernel-level MAC control.

#### Scenario: CSO review
- **WHEN** CSO reads Whitepaper or Troubleshooting Workflow
- **THEN** documentation SHALL state bypass risks (subshells, interpreters) and recommend jump-only prod where possible
