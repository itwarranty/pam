### Requirement: DR service operator SHALL access targets only via PAM jump

SSH PAM SHALL provision a dedicated service operator (default `dr-scanner`) with `access: jump` for automated inventory.

#### Scenario: Service operator provisioning
- **WHEN** `pam_dr_enabled` is `true`
- **THEN** `pam_operators` SHALL include `{{ pam_dr_service_operator_name }}` with `dr_service: true`
- **THEN** operator SHALL use pubkey authentication without interactive MFA
- **THEN** automation private key SHALL be stored at `{{ operators_home }}/<name>/.dr/automation_key` (mode `0600`)
- **THEN** operator SHALL NOT receive target broked identity files

#### Scenario: JIT inventory window
- **WHEN** DR grants a JIT permit for `target_id`
- **THEN** `{{ pam_home }}/.dr/jit/grants.json` SHALL record host, port, expiry, trigger session
- **THEN** `ansible-playbook site.yml --tags dr_jit_sync` SHALL update `permit_open` and `authorized_keys` for `dr-scanner`
- **THEN** permits SHALL expire after `pam_dr_jit_window_minutes`

#### Scenario: DR daemon has no target keys
- **WHEN** DR collects a passport
- **THEN** DR SHALL connect via `ProxyJump` as `dr-scanner`
- **THEN** DR SHALL NOT read `{{ pam_targets_home }}/<id>/identity`
