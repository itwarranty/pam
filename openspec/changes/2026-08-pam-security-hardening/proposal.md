## Why

ITWarranty SSH PAM v1.1.1 implements the required SSH gateway flow, but a
repository audit found gaps between several security guarantees in OpenSpec and
their runtime enforcement:

1. `access: audit` validates a command name and then executes the original line
   through `eval`; shell expansion can therefore run code outside the read-only
   command policy.
2. Command policy v2 forwards input bytes to the child PTY before the complete
   line is approved. The current implementation prevents Enter for a denied
   line, but does not satisfy the stronger specification wording that denied
   input is not forwarded.
3. Session termination targets a wrapper PID instead of the whole gateway
   process group, so descendants may survive an operator kill action.
4. Generated TOTP secrets are not stable across repeated deploys when no
   explicit `mfa_secret` is supplied.
5. Repeated Ansible runs recreate/restart the SSH container even when effective
   configuration is unchanged, disrupting active sessions.
6. Live session watch lacks an executable authorization check, and one default
   runtime path still points to `/home/gateway` instead of `/home/pam`.
7. Aggregated gateway syslog is writable by every local/container user.
8. Documentation and DR examples still contain pre-rebrand names, paths and
   commands that do not match the current PAM contract.

These are not new product features. This change hardens the existing security
boundary and makes the implementation match the guarantees already presented
to operators and customers.

## What Changes

### 1. Replace audit-shell `eval` with structured command execution

- Parse input without shell expansion.
- Resolve only an explicit command allowlist.
- Validate every path argument after parsing.
- Execute an argv vector directly (`execve`/`subprocess` equivalent), never
  `eval`, `sh -c`, command substitution, redirection, pipelines or control
  operators.
- Add negative tests for `$()`, backticks, `${...}`, redirection, semicolon,
  newline, glob and symlink escapes.

### 2. Make command policy v2 a true pre-forward gate

- Buffer an entire logical command before forwarding it to the child PTY.
- Do not forward denied bytes, line terminators or paste fragments.
- Define behavior for CR, LF, CRLF, Ctrl+C, Ctrl+D, backspace, arrow keys,
  UTF-8, bracketed paste and terminal Cursor Position Reports.
- Preserve terminal echo, window resize and signal semantics.
- Remove or explicitly gate the v1 remote `bash --rcfile` fallback.

### 3. Terminate complete session process trees

- Create one process group/session per gateway connection.
- Store `pid` and `pgid` in the session registry.
- Session kill sends TERM to the process group, waits, then optionally sends
  KILL to the same group.
- Verify that `script`, inspector, nested `ssh` and target-side channel close.

### 4. Make MFA secret lifecycle deterministic

- Explicit `operator.mfa_secret` remains authoritative.
- If an operator already has a deployed TOTP secret, repeated deploy preserves
  it.
- Production profile fails closed when neither Vault/config secret nor an
  existing secret is available.
- Secret generation is limited to explicit bootstrap/lab workflows.
- Generated onboarding artifacts must not expose secrets through Ansible logs.

### 5. Make deploys session-safe and idempotent

- Container recreation occurs only when image, mounts, ports, environment or
  effective runtime configuration changes.
- SELinux relabel tasks report `changed` only when labels actually change.
- A planned disruptive restart is visible before execution and can be deferred
  while active sessions exist.
- Verification commands use configured names such as
  `pam_container_name` rather than hard-coded `ssh_pam`.

### 6. Enforce live-watch authorization

- Correct the default registry path to `/home/pam/runtime/sessions`.
- Permit watch only to root or an explicitly configured moderator/audit group.
- Record successful and denied watch attempts.
- Resolve and validate the log path from the registry; reject path traversal
  and symlink escape.

### 7. Tighten audit log permissions

- Replace mode `0666` for `gateway.syslog` with least-privilege ownership and
  group write where required.
- Separate lab-only relaxed permissions from production defaults.
- Verify owner, group, mode and append behavior in compliance checks.

### 8. Align documentation and integrations

- Replace remaining `gateway`, `bastion_*`, `/home/bastion`, `ssh_bastion` and
  obsolete Lima/deploy command examples where they describe the current
  product.
- Document DR's current `pam_dr_*` contract.
- State clearly that OIDC/SAML support is certificate-signing tooling, not a
  runtime IdP in the gateway.
- State clearly that RISK is a separate product and is not yet wired into the
  PAM authentication path.
- Align version references with v1.1.1 or the next release produced by this
  change.

## Capabilities

| Capability | Change |
|:---|:---|
| `pam-audit-readonly-role` | Replace shell evaluation with strict argv execution |
| `pam-gateway-command-policy-v2` | Complete-line pre-forward enforcement and terminal semantics |
| `pam-session-control-plane` | Process-group termination and registry schema |
| `pam-live-session-moderation` | Runtime authorization and safe path resolution |
| `pam-tamper-evident-session-logs` | Least-privilege aggregate log permissions |
| `pam-compliance-verify` | Config-aware verification of all hardening controls |
| `pam-auth-secret-lifecycle` | New capability: deterministic TOTP lifecycle |
| `pam-deployment-safety` | New capability: idempotent, session-aware deployment |
| `pam-documentation-consistency` | New capability: executable docs and naming consistency |

## Impact

- **Container:** audit shell, PTY inspector, gateway wrappers, session registry.
- **Host scripts:** session kill/watch, compliance verification.
- **Ansible:** operator provisioning, SELinux labeling, container lifecycle,
  configured-name usage.
- **Tests/CI:** unit tests for parsers and PTY state machine; container/Lima
  integration tests for auth, kill, watch and idempotence.
- **Docs:** Whitepaper, runbooks, DR contract, release/version references.
- **Compatibility:** session registry gains `pgid`; readers must tolerate both
  old and new records during one release transition.

## Non-Goals

- Adding RDP, web, database or other protocols.
- Building the separate ITWarranty RISK engine inside PAM.
- Replacing OpenSSH, Linux PAM or rootless Podman.
- Implementing a web UI or video replay player.
- Claiming command denylist enforcement as kernel MAC.
- Automatic HA failover or live replication of active sessions.

## Rollout

1. Ship tests that reproduce every finding before implementation changes.
2. Fix P0 boundaries: audit shell, PTY pre-forward gate, process-group kill.
3. Fix MFA lifecycle and deployment idempotence.
4. Fix watch authorization and log permissions.
5. Run Lima acceptance and two-pass Ansible idempotence checks.
6. Update documentation only after runtime behavior is verified.
7. Keep enforcement flags opt-in in lab until acceptance; production must fail
   closed when a required hardening control is unavailable.

## Success Criteria

- Audit-role injection corpus executes no side effects.
- A denied command produces no bytes in the target PTY and no target-side
  command history entry.
- `pam sessions kill <id>` removes the full local process group and closes the
  target SSH channel.
- Two identical Ansible runs preserve TOTP secrets and do not restart the
  container; the second run reports no unexpected changes.
- Unauthorized session watch exits non-zero and emits an audit event.
- Production aggregate logs are not world-writable.
- Static checks plus automated unit/integration tests pass in CI.
- Active documentation contains no current-product references to removed MT or
  bastion naming.
