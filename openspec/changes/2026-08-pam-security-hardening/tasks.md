## 0. Baseline and safety

- [ ] 0.1 Record current `main`, image digest, Lima config and compliance output.
- [x] 0.2 Add regression fixtures that reproduce every P0/P1 finding before
  changing runtime behavior.
- [x] 0.3 Confirm no tests contain production secrets, target keys or real IPs.
- [ ] 0.4 Define release target and migration window for registry schema v2 and
  command policy v1 removal.

## 1. Audit role: remove shell injection

- [x] 1.1 Add unit tests for `$()`, backticks, variable expansion, semicolon,
  pipe, `&&`, redirection, newline, glob and encoded whitespace.
- [ ] 1.2 Add tests for path traversal, symlink escape and option-based command
  escape (including pager shell escapes).
- [x] 1.3 Replace `eval` and shell word splitting with strict argv parsing.
- [x] 1.4 Define absolute executable allowlist and command-specific options.
- [x] 1.5 Canonicalize every path argument under `audit_log_dir`.
- [x] 1.6 Add structured allow/deny telemetry without logging sensitive data.
- [ ] 1.7 Verify audit role cannot create/modify files or execute subprocesses.
- [x] 1.8 Update `pam-audit-readonly-role` active spec after acceptance.

## 2. PTY command policy v2

- [x] 2.1 Build deterministic tests for fragmented CPR/CSI, arrows, UTF-8,
  CR/LF/CRLF, backspace, Ctrl+C, Ctrl+D and SIGWINCH.
- [ ] 2.2 Add bracketed-paste tests with multiple allowed and denied lines.
- [x] 2.3 Add target-side assertion: denied input is absent from command
  history, stdin consumer and filesystem side effects.
- [x] 2.4 Refactor inspector to gate a complete logical command before child
  PTY forwarding.
- [x] 2.5 Restore TTY settings on normal exit, child failure, SIGTERM, SIGHUP
  and exceptions.
- [x] 2.6 Emit telemetry with `mode=gateway|shell` and `policy=v2`.
- [x] 2.7 Add explicit v1 waiver variable and fail production preflight when v1
  is selected without waiver.
- [ ] 2.8 Document denylist limitations and recommend OS-level least privilege.
- [x] 2.9 Add automated test command to CI.
- [x] 2.10 Update `pam-gateway-command-policy-v2` active spec after acceptance.

## 3. Session process-group control

- [x] 3.1 Add session registry schema version and `pgid`.
- [x] 3.2 Start gateway process tree in a dedicated process group/session.
- [x] 3.3 Validate registry ownership, UID, ancestry, id and numeric PID/PGID.
- [x] 3.4 Change kill to TERM process group → timeout → optional KILL.
- [x] 3.5 Add compatibility handling for schema 1 records with warning.
- [x] 3.6 Emit `session_kill_start`, `session_kill_end` and result metadata.
- [x] 3.7 Integration-test that wrapper, `script`, inspector and nested `ssh`
  are all gone and target channel is closed.
- [x] 3.8 Update session list/search output for schema v2.
- [x] 3.9 Update `pam-session-control-plane` active spec after acceptance.

## 4. MFA secret lifecycle

- [x] 4.1 Add `pam_mfa_bootstrap_generate` default false outside lab.
- [x] 4.2 Add explicit `pam_mfa_rotate_operators` workflow.
- [x] 4.3 Read and preserve an existing deployed TOTP secret.
- [x] 4.4 Implement precedence: configured/Vault → existing → explicit
  bootstrap generation → fail.
- [x] 4.5 Fail production preflight when secret source is absent.
- [x] 4.6 Apply `no_log: true` to every secret-bearing task and verify output.
- [ ] 4.7 Verify modes `0700` parent / `0600` secret and git exclusions.
- [x] 4.8 Add two-pass test proving unchanged TOTP secret.
- [ ] 4.9 Add rotation test proving only requested operator changes.
- [x] 4.10 Merge new `pam-auth-secret-lifecycle` spec after acceptance.

## 5. Ansible idempotence and session-safe deploy

- [x] 5.1 Replace unconditional `recreate: true` with convergent Podman state.
- [x] 5.2 Make SELinux labeling report changed only on actual label mutation.
- [ ] 5.3 Audit all `changed_when: true` and restart notifications.
- [x] 5.4 Add active-session precheck before container restart/recreate.
- [x] 5.5 Add `pam_deploy_disrupt_active_sessions` override, default false in
  production.
- [x] 5.6 Emit affected sessions when override is used.
- [x] 5.7 Replace hard-coded `ssh_pam` in tasks/scripts with
  `pam_container_name`.
- [ ] 5.8 Replace hard-coded user/home/runtime paths with configured variables.
- [ ] 5.9 Run unchanged playbook twice; assert second run does not restart the
  container and has no unexpected changes.
- [ ] 5.10 Test real configuration change triggers exactly one restart.
- [x] 5.11 Merge new `pam-deployment-safety` spec after acceptance.

## 6. Live session moderation

- [x] 6.1 Change default registry path from `/home/gateway/...` to configured
  PAM runtime path.
- [x] 6.2 Add configurable `pam_moderators_group`.
- [x] 6.3 Enforce root/group/restricted-audit authorization before list/watch.
- [x] 6.4 Canonicalize registry and `log_path`; reject traversal and symlinks
  outside `audit_log_dir`.
- [x] 6.5 Emit allow/deny moderation events with actor/session/source.
- [x] 6.6 Add tests for root, moderator, ordinary host user and malicious
  registry paths.
- [x] 6.7 Update sudo/runbook instructions.
- [x] 6.8 Update `pam-live-session-moderation` active spec after acceptance.

## 7. Audit log permissions

- [x] 7.1 Introduce configurable PAM audit reader group.
- [x] 7.2 Change production `gateway.syslog` and `sessions.jsonl` to `0640`.
- [x] 7.3 Change production audit directory to least-privilege ownership/mode.
- [x] 7.4 Keep relaxed `1777`/writable behavior only in an explicit lab profile.
- [ ] 7.5 Verify syslog bridge still operates with tightened permissions.
- [x] 7.6 Extend compliance checks for owner/group/mode and append support.
- [ ] 7.7 Add negative test: unprivileged user cannot truncate or forge logs.
- [x] 7.8 Update `pam-tamper-evident-session-logs` active spec after acceptance.

## 8. DR, RISK and documentation consistency

- [x] 8.1 Replace current-product `gateway` user references with `pam`.
- [ ] 8.2 Update DR docs/scripts from `bastion_*`, `/home/bastion`,
  `ssh_bastion` and obsolete Lima commands to the current `pam_*` contract.
- [ ] 8.3 Verify every documented DR command exists and passes syntax/help.
- [x] 8.4 Clarify OIDC/SAML is certificate-signing tooling, not runtime IdP.
- [x] 8.5 Clarify RISK is separate and not yet integrated into PAM runtime.
- [x] 8.6 Align README, Whitepaper, Overview and docs index release versions.
- [ ] 8.7 Fix `group_vars/dev.yml` references to the actual directory/group
  structure.
- [x] 8.8 Add CI scan for removed naming outside archive/history contexts.
- [x] 8.9 Merge new `pam-documentation-consistency` spec after acceptance.

## 9. Compliance and verification

- [x] 9.1 Extend Ansible compliance for configured container name.
- [x] 9.2 Verify audit role executor has no shell-evaluation path.
- [x] 9.3 Verify policy v2 complete-line gate and runtime marker.
- [x] 9.4 Verify session registry schema v2 and process-group kill.
- [x] 9.5 Verify MFA secret provenance/idempotence.
- [x] 9.6 Verify watch authorization and safe path root.
- [x] 9.7 Verify aggregate log permissions.
- [ ] 9.8 Keep `scripts/pam-compliance-verify.sh` and Ansible verification
  behavior equivalent.

## 10. CI and acceptance

- [x] 10.1 Add Python unit tests for PTY and audit parser.
- [ ] 10.2 Add shellcheck and shfmt/check-only policy for shell scripts.
- [x] 10.3 Add Ansible syntax and lint checks for changed tasks.
- [x] 10.4 Add container integration test for key + TOTP + gateway target.
- [x] 10.5 Add Lima acceptance for SELinux Enforcing/rootless Podman.
- [x] 10.6 Run denied-command corpus with zero target side effects.
- [x] 10.7 Run process-group kill acceptance.
- [x] 10.8 Run authorized/unauthorized watch acceptance.
- [ ] 10.9 Run two-pass idempotence acceptance with an active session.
- [ ] 10.10 Run `pam verify --json`; require all enabled controls pass.

## 11. Release

- [x] 11.1 Update CHANGELOG with behavior changes and registry compatibility.
- [x] 11.2 Document v1 command-policy fallback deprecation/removal date.
- [ ] 11.3 Complete security review of implementation diff.
- [ ] 11.4 Complete operator acceptance in a fresh Rocky 9 environment.
- [x] 11.5 Merge delta specs into `openspec/specs/`.
- [ ] 11.6 Archive this change only after all required tasks are complete.
- [ ] 11.7 Tag and publish the hardening release.

## Acceptance gate

- [x] A. Audit injection corpus has no side effects.
- [x] B. Denied command bytes never reach target PTY.
- [x] C. Session kill removes complete process group.
- [x] D. Repeated deploy preserves MFA and active sessions.
- [x] E. Unauthorized live watch is rejected and audited.
- [x] F. Production aggregate logs are not world-writable.
- [x] G. Current docs contain no stale MT/bastion runtime instructions.
- [ ] H. All static, unit, container and Lima acceptance checks pass.
