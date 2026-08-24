## MODIFIED Requirements

### Requirement: Aggregate audit logs SHALL use least privilege

Aggregate session telemetry SHALL be writable only by identities required for
PAM operation and readable only by configured audit readers.

#### Scenario: Production gateway syslog
- **WHEN** `gateway.syslog` is created in production
- **THEN** it SHALL NOT be world-writable
- **AND** owner/group/mode SHALL match configured PAM audit policy

#### Scenario: Production structured log
- **WHEN** `sessions.jsonl` is created in production
- **THEN** only the PAM runtime identity and configured audit readers SHALL
  receive required access

#### Scenario: Lab relaxed permissions
- **WHEN** a lab requires relaxed writable directories
- **THEN** relaxation SHALL be enabled only through an explicit lab profile
- **AND** compliance output SHALL identify lab mode

### Requirement: Tamper evidence SHALL combine permissions and integrity data

Tamper-evident logging SHALL combine least-privilege filesystem controls with
hash/metadata evidence and supported append protections.

#### Scenario: Session closes
- **WHEN** a session log closes
- **THEN** hash and metadata sidecars SHALL be produced as specified
- **AND** file ownership/mode SHALL prevent unauthorized truncation or forgery

#### Scenario: Append-only unsupported
- **WHEN** filesystem/container constraints prevent append-only attributes
- **THEN** verification SHALL report the limitation
- **AND** SHALL NOT claim append-only enforcement solely because sidecars exist

### Requirement: Compliance SHALL verify audit file security

Production compliance SHALL validate aggregate audit ownership, group, mode
and integrity-control status.

#### Scenario: Unsafe mode
- **WHEN** an aggregate audit file is world-writable or owned by an unexpected
  identity
- **THEN** production compliance SHALL fail
