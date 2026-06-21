## ADDED Requirements

### Requirement: Operators MAY restrict authentication source IP addresses

SSH PAM SHALL support optional per-operator network source allowlists.

#### Scenario: Operator allowed_sources field
- **WHEN** administrator configures operator with:
  ```yaml
  allowed_sources:
    - "203.0.113.0/24"
    - "198.51.100.10"
  ```
- **THEN** generated `authorized_keys` SHALL include OpenSSH `from="..."` restriction listing those sources (comma-separated)
- **THEN** jump `restrict,port-forwarding` options SHALL remain when `access: jump`

#### Scenario: No allowed_sources means no from restriction
- **WHEN** `allowed_sources` is absent or empty
- **THEN** `authorized_keys` SHALL NOT include `from=` unless global policy adds it

### Requirement: Global source restriction MAY complement per-operator rules

Defense in depth at firewall layer SHALL be optional.

#### Scenario: firewalld rich rule for bastion port
- **WHEN** `bastion_allowed_source_cidrs` is non-empty
- **THEN** Ansible SHALL configure firewalld to allow `bastion_ssh_port` only from those CIDRs
- **AND** existing port open rule MAY be replaced or narrowed per design in `tasks/configure_source_firewall.yml`

### Requirement: CSO strict mode MAY require source IP on all prod operators

Preflight SHALL support mandatory source restriction for production.

#### Scenario: Strict preflight failure
- **WHEN** `bastion_require_source_ip` is `true`
- **AND** any operator in `bastion_operators` lacks non-empty `allowed_sources`
- **THEN** preflight SHALL fail with explicit operator name

#### Scenario: Lab exempt from strict mode
- **WHEN** inventory uses dev/lab group vars
- **THEN** `bastion_require_source_ip` SHOULD default to `false` unless explicitly overridden

### Requirement: Connection from non-allowed IP SHALL fail closed

Authentication from disallowed network origin MUST NOT succeed.

#### Scenario: SSH from wrong IP with from= restriction
- **WHEN** operator connects from IP not listed in `from="..."`
- **THEN** sshd SHALL reject authentication before MFA prompt

#### Scenario: Firewall blocks before SSH when global CIDR set
- **WHEN** global firewalld CIDR restriction is active
- **AND** client connects from outside allowed CIDR
- **THEN** connection SHALL NOT reach sshd
