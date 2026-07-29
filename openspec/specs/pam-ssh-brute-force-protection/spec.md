### Requirement: Gateway SSH port SHALL support optional rate limiting

SSH PAM SHALL offer host-level protection against authentication abuse on `pam_ssh_port`.

#### Scenario: Rate limit disabled
- **WHEN** `pam_ssh_rate_limit_enabled` is `false` (default)
- **THEN** playbook SHALL NOT alter firewalld rate rules or fail2ban beyond existing Tier 1 source CIDR rules

#### Scenario: Firewalld rate limit enabled
- **WHEN** `pam_ssh_rate_limit_enabled` is `true`
- **AND** `pam_ssh_rate_limit_method` is `firewalld`
- **THEN** Ansible SHALL configure firewalld rich rule with `limit value="{{ pam_ssh_rate_limit_rate }}"` for `pam_ssh_port/tcp`
- **THEN** rule SHALL coexist with `pam_allowed_source_cidrs` when both set

#### Scenario: Fail2ban enabled
- **WHEN** `pam_ssh_rate_limit_method` is `fail2ban`
- **THEN** Ansible SHALL install fail2ban (if absent), deploy jail filter for gateway SSH auth failures, and enable jail
- **THEN** design SHALL document log source (podman/container journal path on Rocky 9)

### Requirement: Rate limit configuration SHALL be verifiable

Compliance tooling SHALL optionally assert rate limit is active when enabled.

#### Scenario: Compliance verify with rate limit on
- **WHEN** `pam_ssh_rate_limit_enabled` is `true`
- **AND** `scripts/pam-compliance-verify.sh` runs
- **THEN** script SHALL verify firewalld rich rule or fail2ban jail active state (method-specific)

### Requirement: Rate limiting SHALL NOT replace MFA or source IP controls

Network rate limit is defense in depth only.

#### Scenario: CSO architecture review
- **WHEN** documentation describes Tier 2 brute-force protection
- **THEN** it SHALL state that MFA strict and optional `allowed_sources` remain primary controls
