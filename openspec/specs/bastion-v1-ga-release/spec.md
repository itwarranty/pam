### Requirement: v1.0.0 SHALL mark GA of SSH PAM as complete SSH PAM product

Release v1.0.0 SHALL bundle Tier 4 capabilities and organizational gates for  internal prod.

#### Scenario: Version tag
- **WHEN** Tier 4 phases A–G complete per tasks.md
- **THEN** git tag `v1.0.0` SHALL be created
- **THEN** CHANGELOG.md SHALL summarize Tiers 1–4

#### Scenario: PKI QA completion
- **WHEN** v1.0.0 is declared
- **THEN** tasks in `ssh-user-ca-qa` §3–5 SHALL be marked complete for internal org CA
- **THEN** `bastion_ssh_user_ca_qa_complete: true` SHALL be set in internal prod group_vars

### Requirement: Product positioning SHALL describe PAM replacement

#### Scenario: Client documentation
- **WHEN** customer reads `docs/SSH-PAM-Overview.md` (renamed from Without-PAM)
- **THEN** text SHALL state SSH PAM / SSH PAM is SSH PAM replacing commercial gateways
- **THEN** text SHALL NOT frame product as «for organizations without PAM»

#### Scenario: Battlecard
- **WHEN** presales opens `docs/Battlecard-SKDPU-SSH.md`
- **THEN** document SHALL compare SSH controls fairly vs СКДПУ Шлюз

#### Scenario: SoW snippet
- **WHEN** legal uses `docs/SoW-SSH-Access.md`
- **THEN** scope SHALL specify SSH, gateway mode for prod interactive, audit obligations

### Requirement: Prod example profile SHALL exist

#### Scenario: New prod deploy
- **WHEN** engineer copies `group_vars/prod.yml.example`
- **THEN** file SHALL enable recommended CSO controls (gateway required, JIT timer, source IP, policy v2)

### Requirement: Compliance verify SHALL cover Tier 3–4 optional checks

#### Scenario: Full verify script
- **WHEN** `bastion-compliance-verify.sh` runs on healthy internal prod
- **THEN** script SHALL include gateway manifest check when targets defined
- **THEN** script MAY include jq presence when session search enabled

### Requirement: Internal prod acceptance checklist SHALL pass

#### Scenario:  internal bastion
- **WHEN** acceptance checklist in tasks.md §10 is executed
- **THEN** all items SHALL pass on internal Rocky 9 deployment before v1.0.0 tag
