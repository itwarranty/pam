### Requirement: Operators SHALL support access mode gateway

SSH PAM SHALL provide `access: gateway` for interactive SSH to whitelisted targets with gateway-originated sessions.

#### Scenario: Gateway operator connects
- **WHEN** operator has `access: gateway`
- **AND** authentication (pubkey/certificate + MFA) succeeds
- **THEN** sshd SHALL apply `ForceCommand /usr/local/bin/pam-ssh-gateway-wrapper.sh`
- **THEN** `AllowTcpForwarding` SHALL be `no`
- **THEN** `authorized_keys` SHALL NOT include `restrict,port-forwarding`

#### Scenario: Gateway operator attempts ProxyJump
- **WHEN** operator has `access: gateway`
- **AND** client attempts TCP forwarding or ProxyJump
- **THEN** sshd SHALL deny forwarding per `AllowTcpForwarding no`

#### Scenario: Target not in permit_open
- **WHEN** gateway wrapper resolves operator targets
- **AND** no `pam_targets` entry matches `permit_open`
- **THEN** connection SHALL fail with clear error
- **THEN** failure SHALL be logged via syslog tag `gateway-gateway`

### Requirement: Gateway SHALL only allow targets from operator permit_open

Least privilege from Tier 1 SHALL apply to gateway mode.

#### Scenario: Operator has two permit_open entries
- **WHEN** operator `permit_open` lists `10.0.1.10:22` and `10.0.1.11:22`
- **THEN** gateway menu SHALL offer only those targets
- **THEN** connection to `10.0.1.99` SHALL be impossible

#### Scenario: Single permitted target
- **WHEN** operator has exactly one resolvable target
- **THEN** gateway wrapper SHALL connect without interactive menu

### Requirement: Gateway access enum SHALL be validated at preflight

#### Scenario: Invalid access value
- **WHEN** operator `access` is not one of `jump`, `shell`, `audit`, `gateway`
- **THEN** preflight SHALL fail

#### Scenario: Gateway in commercial PAM branch
- **WHEN** `is_commercial_pam` is `true`
- **AND** operator has `access: gateway`
- **THEN** preflight SHALL fail until commercial integration spec defines gateway behavior
