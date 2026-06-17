## Why

MT: Bastion **v1.0.0** delivers complete SSH PAM with **offline TOTP** as second factor. CSO review identified phishing of operator SSH private keys as residual risk. Commercial PAM (Teleport, СКДПУ) markets **FIDO2 / platform authenticators** (Touch ID, YubiKey).

**Goal:** adopt **FIDO-Anchor + Bastion TOTP** — phishing-resistant first factor on the **client workstation**, keep **offline TOTP** on bastion, optional **short-lived SSH user certificates** aligned with JIT windows. **No** WebAuthn in container PAM, **no** `tsh`-like client, **no** IdP runtime dependency on bastion (IdP path remains separate Tier 4 opt-in).

## What Changes

### 1. FIDO2 SSH operator keys (client-side)

- Document and enforce (opt-in prod) `ssh-keygen -t ed25519-sk -O verify-required` operator keys.
- Preflight: `bastion_require_fido_pubkey: true` rejects non-`sk-ssh-*` pubkeys (waiver flag).
- Compliance verify: same check against deployed `authorized_keys` in container.

### 2. MFA policy modes

| Mode | Factors | Default |
|:---|:---|:---:|
| `totp` | pubkey/cert + TOTP | legacy until FIDO rollout |
| `fido_totp` | FIDO-sk pubkey/cert + TOTP | **prod recommended** |
| `fido_only` | FIDO-sk only | CSO waiver only (`bastion_fido_only_waiver: true`) |

- `bastion_mfa_mode` in `group_vars/all.yml` (default `totp`; `prod.yml.example` → `fido_totp`).
- `bastion_mfa_enforce: true` unchanged; `fido_only` relaxes PAM only with waiver.

### 3. JIT-aligned certificate signing for FIDO keys

- Extend `scripts/sign-operator-cert.sh.example` with optional `-V` from operator `valid_until` / `valid_from`.
- New `scripts/sign-operator-cert-jit.sh.example` for JIT window signing of **sk** pubkeys.
- Preflight: when `bastion_require_fido_pubkey` and certificate mode, cert MUST be backed by sk key (`ssh-keygen -Lf`).

### 4. Lab and migration

- `group_vars/dev/`: keep `bastion_require_fido_pubkey: false` (existing `.lab` keys).
- Optional `group_vars/dev/fido_lab.yml` + `engineer-fido` lab operator with sk key fixture (generate in `dev-up.sh` if `BASTION_FIDO_LAB=1`).
- Migration doc: phased rollout lab → pilot prod → `bastion_require_fido_pubkey: true`.

### 5. Documentation and Policy Gate

- Whitepaper Policy Gate #32–33 (FIDO anchor, MFA modes).
- `docs/MT-Bastion-FIDO-Onboarding.md` (operator + CSO).
- Engineer-Onboarding §FIDO; CSO Demo optional block.
- Battlecard row vs Teleport (FIDO without tsh).

## Capabilities

| Capability | Spec |
|:---|:---|
| FIDO-Anchor MFA | `specs/bastion-fido-anchor-mfa/spec.md` |

## Impact

- **Tasks:** `tasks/preflight_cso.yml`, `tasks/verify_compliance_cso.yml`
- **Scripts:** `scripts/bastion-compliance-verify.sh`, `scripts/preflight-fido-key.py`, signing examples
- **Vars:** `group_vars/all.yml`, `group_vars/prod.yml.example`, `group_vars/dev/policy.yml`
- **Docs:** FIDO onboarding, Whitepaper, README releases `v1.1.0`

## Non-Goals

- WebAuthn / biometric PAM inside bastion container.
- Custom `mt-ssh` client (Teleport parity).
- Replacing TOTP by default without CSO waiver.
- IdP WebAuthn as mandatory path (remains Tier 4 OIDC opt-in).
- FIDO for **target** keys (`bastion_targets`) — operator auth only.
- Hardware token provisioning / MDM integration (organizational).

## Success Criteria

- [ ] Prod profile documents `ed25519-sk -O verify-required` onboarding.
- [ ] Preflight fails non-sk pubkey when `bastion_require_fido_pubkey: true`.
- [ ] Compliance verify reports `fido_pubkey` PASS/FAIL.
- [ ] Lab: optional FIDO operator login with sk key + TOTP.
- [ ] JIT cert signing example produces cert valid only inside `valid_until` window.
- [ ] `fido_only` blocked unless `bastion_fido_only_waiver: true`.
- [ ] Merge spec to `openspec/specs/`; tag `v1.1.0`.
