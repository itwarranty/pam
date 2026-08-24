## ADDED Requirements

### Requirement: TOTP secret source SHALL be deterministic

The effective operator TOTP secret SHALL use this precedence:

1. explicit protected inventory/Vault value;
2. existing deployed secret for the same operator;
3. generated value only in explicit bootstrap mode;
4. otherwise fail.

#### Scenario: Explicit secret
- **WHEN** `operator.mfa_secret` is configured
- **THEN** it SHALL be authoritative
- **AND** repeated deploys SHALL preserve it

#### Scenario: Existing deployed secret
- **WHEN** no explicit secret is provided but the operator already has a valid
  deployed `.google_authenticator`
- **THEN** ordinary deploy SHALL preserve the existing secret

#### Scenario: Production has no secret source
- **WHEN** production deploy has neither explicit/Vault nor existing secret
- **THEN** preflight SHALL fail
- **AND** SHALL NOT silently generate a replacement

#### Scenario: Lab bootstrap
- **WHEN** explicit bootstrap generation is enabled in lab/eval
- **THEN** a new secret MAY be generated once
- **AND** subsequent unchanged deploys SHALL preserve it

### Requirement: MFA rotation SHALL be explicit

SSH PAM SHALL rotate TOTP secrets only through an operator-selected,
auditable rotation workflow.

#### Scenario: Requested operator rotation
- **WHEN** an operator is explicitly selected for rotation
- **THEN** only that operator's secret SHALL change
- **AND** onboarding output and audit telemetry SHALL be produced

#### Scenario: Ordinary deploy
- **WHEN** no rotation is requested
- **THEN** no existing operator secret SHALL change

### Requirement: MFA secrets SHALL not leak

SSH PAM SHALL protect MFA secret values in automation output, storage and
version-control workflows.

#### Scenario: Ansible output
- **WHEN** secret-bearing tasks execute
- **THEN** secret values SHALL be suppressed from stdout, diffs and errors

#### Scenario: Secret files
- **WHEN** secret or onboarding files are written
- **THEN** parent/file permissions SHALL be least privilege
- **AND** paths SHALL be excluded from version control
