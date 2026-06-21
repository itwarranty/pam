## 1. Variables and defaults (Phase A — v1.1.0-alpha)

- [x] 1.1 Add to `group_vars/all.yml`:
  - `bastion_require_fido_pubkey: false` (default)
  - `bastion_mfa_mode: totp` (`totp` | `fido_totp` | `fido_only`)
  - `bastion_fido_only_waiver: false`
  - `bastion_fido_ecdsa_sk_allowed: false`
  - `bastion_fido_waiver_operators: []`
  - `bastion_fido_lab_enabled: false`
- [x] 1.2 Update `group_vars/prod.yml.example`: `bastion_require_fido_pubkey: true`, `bastion_mfa_mode: fido_totp`.
- [x] 1.3 Ensure `group_vars/dev/policy.yml` keeps `bastion_require_fido_pubkey: false`.

## 2. Preflight (Phase B)

- [x] 2.1 Create `scripts/preflight-fido-key.py` — validate pubkey line or cert path is FIDO-sk backed; exit 0/1.
- [x] 2.2 Add `tasks/preflight_fido_operators.yml`; include from `preflight_cso.yml` when `bastion_require_fido_pubkey`.
- [x] 2.3 Fail `bastion_mfa_mode: fido_only` without `bastion_fido_only_waiver: true`.
- [x] 2.4 Fail `fido_only` if `bastion_require_fido_pubkey: false`.
- [x] 2.5 Warn (debug) for operators in `bastion_fido_waiver_operators` when strict FIDO enabled.
- [x] 2.6 Unit-test `preflight-fido-key.py` with fixture pubkey lines (sk vs ed25519).

## 3. sshd / MFA mode (Phase C)

- [x] 3.1 Update `templates/sshd_config.j2`: conditional `AuthenticationMethods` for `fido_only` + waiver.
- [x] 3.2 Preflight assert `bastion_mfa_enforce: true` still required except documented fido_only path.
- [x] 3.3 Document that container image unchanged for fido_totp (no Containerfile change required).

## 4. Compliance verify (Phase D)

- [x] 4.1 Extend `scripts/bastion-compliance-verify.sh` — check `fido_pubkey` when `BASTION_REQUIRE_FIDO_PUBKEY=1` or vars file on host.
- [x] 4.2 Extend `tasks/verify_compliance_cso.yml` with FIDO operator checks.
- [x] 4.3 Pass message suitable for CSO demo screen share.

## 5. JIT certificate signing (Phase E)

- [x] 5.1 Extend `scripts/sign-operator-cert.sh.example` — optional 4th arg `valid_until` ISO for `-V -1d:...`.
- [x] 5.2 Create `scripts/sign-operator-cert-jit.sh.example` — read operator name + paths from env/YAML snippet; FIDO-sk aware.
- [x] 5.3 Document interaction with `bastion_cert_max_validity_hours` and JIT `valid_until`.
- [x] 5.4 OpenSpec cross-ref: `bastion-jit-access-windows`, `bastion-ssh-user-cert-operators`.

## 6. Lab (Phase F — optional)

- [x] 6.1 Create `group_vars/dev/fido_lab.yml` + merge in `operators_merge.yml` when enabled.
- [x] 6.2 `dev-up.sh`: if `BASTION_FIDO_LAB=1`, generate `lab/keys/engineer-fido.lab` (sk) or print skip instructions.
- [x] 6.3 CSO Demo optional Block — FIDO login (skip if no hardware).

## 7. Documentation (Phase G)

- [x] 7.1 Create `docs/FIDO-Onboarding.md` (RU): generation, Touch ID/YubiKey, Ansible, pilot, waivers, audit text.
- [x] 7.2 Update `docs/Whitepaper.md` — Policy Gate #32–33, Executive MFA paragraph.
- [x] 7.3 Update `docs/Engineer-Onboarding.md` §FIDO.
- [x] 7.4 Update `docs/README.md` index + releases row `v1.1.0`.
- [x] 7.5 Update `docs/Battlecard-SKDPU-SSH.md` — row FIDO2 / platform key.
- [x] 7.6 Update root `README.md` releases table.

## 8. Release (Phase H)

- [x] 8.1 Merge `specs/bastion-fido-anchor-mfa/spec.md` → `openspec/specs/bastion-fido-anchor-mfa/spec.md`.
- [x] 8.2 Archive change to `openspec/changes/archive/2026-06-bastion-fido-anchor-mfa/`.
- [x] 8.3 Update `openspec/config.yaml` — Tier 5 FIDO complete.
- [x] 8.4 `CHANGELOG.md` entry v1.1.0.
- [ ] 8.5 Tag `v1.1.0` (after user approval).

## 9. Acceptance (release gate)

- [ ] 9.1 Lab deploy with `bastion_require_fido_pubkey: false` — regression: jump/shell/gateway still work.
- [ ] 9.2 Manual: FIDO-sk operator + TOTP login on Lima lab (if hardware available).
- [ ] 9.3 Preflight fail: non-sk pubkey when `bastion_require_fido_pubkey: true`.
- [ ] 9.4 Compliance verify `fido_pubkey` PASS with sk operators, FAIL without.
- [ ] 9.5 `fido_only` without waiver — preflight fail.
- [ ] 9.6 `ansible-playbook --syntax-check` + CI green.
