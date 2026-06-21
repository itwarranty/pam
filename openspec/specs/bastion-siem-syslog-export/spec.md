## ADDED Requirements

### Requirement: Gateway host SHALL optionally forward security events to client SIEM via syslog

SSH PAM SHALL configure host-level rsyslog forwarding when enabled — without requiring Internet access from the bastion container.

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
  - `bastion_session_logs` — writes to `audit_log_dir`
  - `bastion_ssh_connect` — connect syscalls

#### Scenario: CSO documentation maps keys to SIEM use cases
- **WHEN** client security team onboards SIEM
- **THEN** design appendix SHALL map each key to recommended alert (e.g. session log tamper attempt, outbound connect anomaly)

### Requirement: SSH PAM SHALL NOT ship a proprietary SIEM application

Product scope is forwarder configuration and documentation only.

#### Scenario: No  cloud SIEM
- **WHEN** Tier 1 SIEM capability is enabled
- **THEN** all log data SHALL remain under client custody on client SIEM infrastructure

## Appendix: Suggested SIEM field mapping (informational)

| Source | Field / key | Suggested use |
|:---|:---|:---|
| auditd | `bastion_session_logs` | Alert on unexpected delete/rename in session log dir |
| auditd | `bastion_ssh_connect` | Correlate outbound connections from bastion UID |
| sidecar `.sha256` | GNU hash line | `sha256sum -c` before ticket attach |
| sidecar `.meta` | `SHA256`, `USER`, `INCIDENT`, `CLIENT` | Ticket metadata / client parser |
| rsyslog | `local6.*` | Route auditd plugin events to client SIEM receiver |

### CEF mapping (client SIEM — not embedded in SSH PAM)

| CEF extension | Source | Example value |
|:---|:---|:---|
| `deviceVendor` | static | `` |
| `deviceProduct` | static | `SSH PAM` |
| `deviceEventClassId` | audit key | `bastion_session_logs` |
| `name` | audit syscall | `write session log` |
| `sourceUserName` | audit uid | operator Unix name |
| `fileHash` | `.meta` sidecar | SHA256 hex |

CEF conversion SHALL be performed by client SIEM vendor rules — not embedded in SSH PAM.
