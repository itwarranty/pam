## Context

The SSH gateway is a chain of trust:

```text
operator ssh client
  → Rocky host :2222 / rootless Podman publish
  → container OpenSSH (pubkey + TOTP/FIDO policy)
  → Match User / ForceCommand
  → gateway or audit wrapper
  → PTY inspector / session recorder
  → target ssh
```

The gateway must preserve normal terminal behavior while enforcing controls
before actions cross the audit boundary. Ansible is also part of that boundary:
it creates authentication material and may interrupt sessions by recreating the
container.

This design addresses the findings without changing the SSH-only, Air Gap,
Rocky 9, SELinux Enforcing and rootless Podman product constraints.

---

## D1: Audit role command execution

### Problem

The current audit shell extracts the first token, validates it, and later runs
the original input through `eval`. Validation and execution therefore operate
on different representations. Shell substitutions can execute during argument
iteration or `eval`.

### Decision

Use a strict parser that accepts a deliberately small grammar:

```text
command := executable *(SP argument)
argument := plain UTF-8 text without shell metacharacters
```

Rejected syntax includes:

- `$()`, backticks and variable expansion;
- `;`, `&`, `|`, newline and NUL;
- `<`, `>`, process substitution;
- globs unless a command-specific rule explicitly supports them;
- options that cause an allowed utility to execute programs or write files.

The parser returns an argv list. The executor maps argv[0] to an absolute,
compiled/configured allowlist and invokes it directly. The original command
string is never passed to a shell.

### Command-specific policy

Each allowed command has:

- absolute executable path;
- accepted options;
- path-bearing argument positions;
- whether an argument may be absent;
- maximum output/time limits where practical.

Path validation uses canonical paths and refuses symlinks that resolve outside
`audit_log_dir`. Commands such as `less` must disable shell escapes and unsafe
features through fixed environment/options, or be removed from the allowlist.

### Failure behavior

Parse or policy failure returns a generic denial, emits structured audit
telemetry, and executes nothing.

---

## D2: PTY command policy v2

### Problem

The current inspector forwards printable bytes as they arrive, then checks the
accumulated line at CR/LF. A denied command cannot normally be submitted with
Enter, but target-side line editing and control characters already received the
input. This does not meet the existing "before forward" design claim.

### Decision: line-gated relay

Use two distinct paths:

1. **Input policy path:** buffer one logical command locally; do not forward
   command bytes until accepted.
2. **Output path:** relay child PTY output immediately after terminal-control
   sanitization required for known IDE CPR artifacts.

On accepted Enter:

```text
buffer → deny/allow evaluation → write(buffer + terminator) to child PTY
```

On denied Enter:

```text
buffer → audit event → clear buffer → no write to child PTY
```

### Terminal state machine

The implementation SHALL define and test:

| Input | Behavior |
|:---|:---|
| UTF-8 printable bytes | Append to local buffer; locally render safely |
| Backspace/Delete | Remove one logical character, update local rendering |
| CR/LF/CRLF | Submit exactly one logical line |
| Ctrl+C | Clear pending buffer; send SIGINT only to running child command when applicable |
| Ctrl+D | Exit only with empty buffer; otherwise delete/ignore per shell semantics |
| Arrow/history keys | Either implement local history or explicitly ignore; never forward partial CSI as command text |
| Bracketed paste | Split into logical lines and evaluate every line |
| CPR `ESC[row;colR` | Drop only when recognized as unsolicited CPR |
| SIGWINCH | Copy outer terminal size to child PTY |

The inspector must restore the outer TTY in every exit path, including
exceptions and signals.

### Security limitation

A denylist remains a compensating control, not a shell sandbox or MAC policy.
Interpreters, encoded payloads and allowed commands with dangerous semantics
remain possible. Production guidance continues to prefer gateway workflows with
least-privilege target accounts and OS-level controls.

### v1 fallback

The remote `bash --rcfile` path is disabled in production. If retained for one
migration release, it requires:

- an explicit `pam_command_policy_v1_waiver: true`;
- preflight warning/fail-closed policy;
- telemetry identifying `policy=v1`;
- removal date documented in CHANGELOG.

---

## D3: Session lifecycle and kill semantics

### Problem

The registry stores the shell wrapper PID, while the active chain contains
`script`, inspector and `ssh` descendants. Killing one PID is not a reliable
session termination primitive.

### Decision

Create a dedicated process group for each gateway session and store:

```json
{
  "schema": 2,
  "id": "...",
  "pid": 123,
  "pgid": 123,
  "operator": "...",
  "target_id": "...",
  "started_at": "...",
  "log_path": "..."
}
```

The session control command validates that:

- the registry file is owned by the PAM runtime user;
- `pgid` is numeric and maps to the expected gateway process tree;
- the process belongs to the configured PAM user;
- the registry path and session id contain no traversal.

Kill algorithm:

1. send `SIGTERM` to `-pgid`;
2. wait up to `pam_kill_timeout`;
3. verify no members remain;
4. send `SIGKILL` to `-pgid` if configured;
5. emit `session_kill_start/end` with result;
6. remove stale registry only after verification.

Readers accept schema 1 records temporarily, but schema 1 kill emits a warning
and uses a descendant-walk fallback.

---

## D4: MFA secret lifecycle

### Source precedence

1. Explicit `operator.mfa_secret` from protected inventory/Vault.
2. Existing deployed `.google_authenticator` secret for the same operator.
3. Generated secret only when `pam_mfa_bootstrap_generate: true`.
4. Otherwise fail.

Production profile sets bootstrap generation to false. Eval/lab may enable it.

### Idempotence

Provisioning first checks for an existing secret and preserves it unless
`pam_mfa_rotate_operators` explicitly includes the operator. Rotation is a
separate operation with onboarding output and audit event, not a side effect of
ordinary deploy.

### Secret handling

- `no_log: true` for all secret-bearing Ansible tasks.
- Generated files mode `0600`, parent directory `0700`.
- No secret in syslog, JSONL, command line or diff output.
- Controller-side onboarding artifacts are explicitly documented and excluded
  from git.

---

## D5: Session-safe Ansible deployment

### Container lifecycle

Remove unconditional `recreate: true`. Podman module convergence determines
whether recreation is needed. Configuration templates notify a restart handler
only when content changes.

Before a disruptive action:

1. read active session registry;
2. if sessions exist and `pam_deploy_disrupt_active_sessions=false`, fail with
   actionable output;
3. if override is true, log affected sessions and continue.

### SELinux

Prefer declarative `sefcontext` plus `restorecon`. If `chcon` remains, compare
the current context first and mark changed only on actual mutation.

### Configured names

All runtime and verification tasks use:

- `pam_container_name`;
- `pam_user`;
- `pam_home`;
- `pam_runtime_dir`;
- `audit_log_dir`.

Hard-coded defaults are allowed only in variable declarations, not operational
commands.

### Two-pass acceptance

The same playbook is run twice with unchanged inputs:

- run 1 converges;
- run 2 has no container restart/recreate, no MFA change, and no unexpected
  changed tasks.

---

## D6: Live session moderation

### Authorization

Host-side watch is allowed only when one condition holds:

- effective UID is root; or
- caller belongs to `pam_moderators_group`; or
- invocation passes through an audited restricted command mapped to an
  `access: audit` operator.

The script does not infer authorization from possession of a session id.

### Safe log resolution

`log_path` is read from a validated registry record, canonicalized, and must be
under `audit_log_dir`. Symlinks and traversal outside that root are rejected.

Defaults derive from installed configuration (`/etc/ssh-pam/pam_root` or an
installed env file); no `/home/gateway` fallback remains.

Every allow/deny attempt records actor, session, source and outcome.

---

## D7: Log ownership and integrity

Production defaults:

```text
audit_log_dir       0750 pam:pam-audit
gateway.syslog      0640 pam:pam-audit
sessions.jsonl      0640 pam:pam-audit
session registry    0750 pam:pam
```

Exact group names remain configurable. Lab may use relaxed modes only through a
clearly named lab variable/profile.

`chattr +a` is defense in depth, not the only access control. Compliance checks
must validate mode and ownership and report whether append-only attributes are
supported.

---

## D8: Testing strategy

### Unit tests

- Audit parser injection corpus and path canonicalization.
- PTY state machine with byte-fragmented CSI/CPR, UTF-8, paste, CRLF,
  backspace, Ctrl+C/D and resize.
- Session registry schema and process-group validation.
- MFA source precedence.

### Container integration

- Real OpenSSH auth: key + TOTP.
- Gateway command accepted/denied behavior.
- Denied command absent from target history and side effects.
- Kill closes nested target channel.
- Watch authorization allow/deny.

### Ansible/Lima acceptance

- Rocky 9 x86_64, SELinux Enforcing, rootless Podman.
- Two identical deploy passes.
- Existing active session blocks disruptive deploy unless override.
- `pam verify` and Ansible compliance both pass.

CI may run static/unit tests on every change; Lima acceptance may be a
separately triggered job due to QEMU duration.

---

## D9: Documentation source of truth

- Product/runtime naming comes from `group_vars/all.yml`.
- Current release comes from CHANGELOG/tag.
- DR examples must use the actual PAM integration contract and existing files.
- OIDC/SAML wording must distinguish certificate tooling from runtime IdP.
- RISK docs must state external integration status without implying a deployed
  pre-auth gate.

A CI documentation scan rejects removed current-product identifiers outside
explicit historical/archive contexts.

---

## Risks and trade-offs

| Risk | Mitigation |
|:---|:---|
| Line buffering changes interactive shell editing | PTY state-machine tests; keep scope explicit; evaluate a maintained PTY library if custom code remains fragile |
| Process-group kill targets wrong process | Validate UID, ancestry, session id and registry ownership before signaling |
| Preserving existing TOTP may preserve compromised secret | Explicit audited rotation workflow |
| Session-safe deploy blocks urgent patch | Document override with forced audit event |
| Tight log permissions break lab bridge | Separate lab profile and integration test |
| Removing v1 fallback breaks legacy targets | Time-limited waiver with telemetry and documented removal |
