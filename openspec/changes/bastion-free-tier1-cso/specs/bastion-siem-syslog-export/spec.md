## ADDED Requirements

### Requirement: Bastion host SHALL optionally forward security events to client SIEM via syslog

MT: Bastion Free SHALL configure host-level rsyslog forwarding when enabled — without requiring Internet access from the bastion container.

#### Scenario: SIEM forwarding disabled by default
- **WHEN** `bastion_siem_forward_enabled` is `false` (default)
- **THEN** playbook SHALL NOT modify client syslog beyond auditd rules already deployed
- **THEN** deployment SHALL succeed

#### Scenario: SIEM forwarding enabled
- **WHEN** `bastion_siem_forward_enabled` is `true`
- **AND** `bastion_siem_server` is set
- **THEN** Ansible SHALL deploy rsyslog drop-in configuration to forward `local6.*` (auditd bastion keys) to `bastion_siem_server:bastion_siem_port`
- **THEN** rsyslog service SHALL be restarted/reloaded

#### Scenario: Air Gap client SIEM on internal network
- **WHEN** SIEM receiver is on client internal IP only
- **THEN** forwarder SHALL use client-supplied protocol (`tcp`, `udp`, or `relp` as documented)
- **THEN** no cloud/SaaS endpoint SHALL be hardcoded in product

### Requirement: Audit events for bastion SHALL use documented auditd keys

SIEM normalization SHALL rely on stable auditd key names already deployed.

#### Scenario: Required audit keys present
- **WHEN** bastion is deployed per current playbook
- **THEN** audit rules SHALL include keys at minimum:
  - `mt_bastion_session_logs` — writes to `audit_log_dir`
  - `mt_bastion_ssh_connect` — connect syscalls

#### Scenario: CSO documentation maps keys to SIEM use cases
- **WHEN** client security team onboards SIEM
- **THEN** design appendix SHALL map each key to recommended alert (e.g. session log tamper attempt, outbound connect anomaly)

### Requirement: MT Bastion Free SHALL NOT ship a proprietary SIEM application

Product scope is forwarder configuration and documentation only.

#### Scenario: No MT Global cloud SIEM
- **WHEN** Tier 1 SIEM capability is enabled
- **THEN** all log data SHALL remain under client custody on client SIEM infrastructure

## Appendix: Suggested SIEM field mapping (informational)

| Source | Field / key | Suggested use |
|:---|:---|:---|
| auditd | `mt_bastion_session_logs` | Alert on unexpected delete/rename in session log dir |
| auditd | `mt_bastion_ssh_connect` | Correlate outbound connections from bastion UID |
| sidecar `.sha256` | `SHA256`, `USER`, `INCIDENT` | Ticket attachment integrity verification (manual or client parser) |

CEF conversion SHALL be performed by client SIEM vendor rules — not embedded in MT: Bastion.
