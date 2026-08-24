### Requirement: Current documentation SHALL match runtime naming

Current operational documentation SHALL use the names and paths implemented by
the active PAM configuration.

#### Scenario: Current product instruction
- **WHEN** documentation describes an executable current PAM workflow
- **THEN** user, container, paths and variables SHALL match current
  `pam_*` configuration
- **AND** removed MT/bastion naming SHALL appear only in explicitly historical
  archive context

### Requirement: Documented commands SHALL be executable

Every command presented as an executable workflow SHALL reference artifacts
that exist and accept the documented arguments.

#### Scenario: Runbook command validation
- **WHEN** a runbook references a script, playbook, inventory or tag
- **THEN** that artifact SHALL exist
- **AND** its documented syntax/help path SHALL pass automated validation

### Requirement: Integration scope SHALL be stated accurately

Documentation SHALL distinguish implemented runtime integrations from examples,
contracts and future work.

#### Scenario: DR documentation
- **WHEN** DR integration is described
- **THEN** it SHALL use the current `pam_dr_*`, `dr-scanner`, `pam-prod` and PAM
  runtime contract

#### Scenario: OIDC/SAML documentation
- **WHEN** OIDC/SAML is described
- **THEN** documentation SHALL distinguish certificate-signing examples from a
  runtime IdP service in the gateway

#### Scenario: RISK documentation
- **WHEN** RISK is mentioned by PAM
- **THEN** it SHALL be identified as a separate product/module
- **AND** documentation SHALL not claim pre-auth enforcement until an actual
  PAM integration is implemented and verified

### Requirement: Release references SHALL be consistent

Current-version statements SHALL agree across release and product
documentation.

#### Scenario: Published version
- **WHEN** README, Overview, Whitepaper and docs index state a current version
- **THEN** it SHALL match CHANGELOG and the intended release tag

### Requirement: Documentation drift SHALL be checked in CI

Automated checks SHALL detect prohibited legacy naming in current operational
documentation while allowing explicit archive/history context.

#### Scenario: Removed current-product identifier
- **WHEN** a prohibited legacy identifier appears outside approved archive or
  historical context
- **THEN** documentation CI SHALL fail with file and line
