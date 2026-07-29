### Requirement: Gateway command policy SHALL enforce denylist on the gateway side (v2)

When v2 is enabled, SSH PAM SHALL inspect operator input before forwarding to target SSH, without injecting rc files on target.

#### Scenario: v2 enabled for gateway
- **WHEN** `pam_gateway_command_policy_v2_enabled` is `true`
- **AND** `pam_shell_command_policy_enabled` is `true`
- **THEN** `pam-ssh-gateway-exec.sh` SHALL use PTY inspector pipeline instead of remote `bash --rcfile` injection

#### Scenario: Denied command
- **WHEN** operator types line matching denylist regex
- **THEN** line SHALL NOT be forwarded to target ssh
- **THEN** syslog tag `pam-deny` SHALL include `MODE=gateway` and `policy=v2`

#### Scenario: Optional session kill on deny
- **WHEN** `pam_gateway_deny_kill_session` is `true`
- **AND** denied command matches
- **THEN** gateway session SHALL terminate within documented timeout

### Requirement: Shell role SHALL reuse same inspector when v2 enabled

#### Scenario: access shell with v2
- **WHEN** `pam_shell_command_policy_v2_enabled` is `true`
- **THEN** `pam-shell-wrapper.sh` SHALL use same inspector for bash session

### Requirement: v1 remote rc path SHALL remain as fallback

#### Scenario: v2 disabled
- **WHEN** `pam_gateway_command_policy_v2_enabled` is `false`
- **THEN** Tier 2/3 remote rc injection behavior SHALL remain unchanged

### Requirement: Limitations SHALL be documented

#### Scenario: CSO review
- **WHEN** reading Whitepaper command policy section
- **THEN** documentation SHALL describe v2 as stronger than v1 but not kernel MAC; paste/multi-line bypass risks remain
