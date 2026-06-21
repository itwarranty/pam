### Requirement: Jump and gateway modes SHALL coexist with documented semantics

SSH PAM SHALL NOT remove `access: jump` when gateway is introduced.

#### Scenario: Jump operator unchanged
- **WHEN** operator has `access: jump`
- **THEN** behavior SHALL remain transparent ProxyJump with `restrict,port-forwarding` (Tier 1 semantics)
- **THEN** target PTY recording SHALL NOT be required

#### Scenario: Documentation distinguishes modes
- **WHEN** CSO reads Whitepaper §4
- **THEN** documentation SHALL state jump = connect-audit; gateway = full target session audit

### Requirement: Production MAY require gateway for interactive prod targets

Optional strict policy SHALL be enforceable via Ansible variables.

#### Scenario: bastion_prod_require_gateway enabled
- **WHEN** `bastion_prod_require_gateway` is `true`
- **AND** operator has `access: jump`
- **AND** operator `permit_open` intersects targets tagged `prod` (default tag check)
- **THEN** preflight SHALL fail unless operator has `bastion_jump_approved: true` CSO waiver flag

#### Scenario: Gateway operator on prod target
- **WHEN** `bastion_prod_require_gateway` is `true`
- **AND** operator accesses prod-tagged target
- **THEN** operator SHALL have `access: gateway`

### Requirement: Jump waiver SHALL be explicit when risk acceptance required

#### Scenario: bastion_jump_risk_acceptance_required
- **WHEN** `bastion_jump_risk_acceptance_required` is `true`
- **AND** operator has `access: jump`
- **THEN** operator entry SHALL include `bastion_jump_approved: true` or preflight SHALL fail
- **THEN** fail message SHALL cite connect-audit-only limitation

### Requirement: Compliance verify SHALL report access mode policy

#### Scenario: Verify with gateway policy enabled
- **WHEN** `bastion_prod_require_gateway` is `true`
- **AND** compliance verify runs
- **THEN** verify SHALL confirm no non-waived jump operators target prod tags (or document manual check)
