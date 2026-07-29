# Design: FIDO-Anchor + gateway TOTP

## Context

Current auth stack (unchanged core):

```
sshd: AuthenticationMethods publickey,keyboard-interactive
PAM:  pam_google_authenticator.so (MFA_STRICT=1)
```

Operators authenticate with `pubkey` or SSH **user certificate** (`TrustedUserCAKeys`) plus TOTP.

## Decision: client-side FIDO, not server-side WebAuthn

| Approach | Verdict |
|:---|:---|
| `ed25519-sk` / `ecdsa-sk` OpenSSH keys with `verify-required` | **Adopt** |
| `pam_u2f` in Alpine container | Reject — USB-only, no platform Touch ID in SSH PTY |
| WebAuthn in PAM on the gateway | Reject — non-standard, breaks Air Gap audit story |
| IdP WebAuthn → SSH cert | Keep Tier 4 opt-in; not part of this change |

**Rationale (CSO):** Platform biometric (Touch ID, Windows Hello) gates **use of private key** on managed laptop. Gateway sees standard OpenSSH `sk-ssh-ed25519@openssh.com` public key — auditable, no new runtime deps.

## Key types

| Type | Use |
|:---|:---|
| `ed25519-sk` | **Default** — prefer for new operators |
| `ecdsa-sk` | Allowed when `pam_fido_ecdsa_sk_allowed: true` |

Preflight SHALL accept pubkeys matching regex `^sk-ssh-ed25519@openssh\.com ` or (optional) `^sk-ecdsa-sha2-nistp256@openssh\.com `.

Certificate mode: run `ssh-keygen -Lf <cert>` on controller; stdout MUST contain `(ssh-ed25519-sk)` or allowed ecdsa-sk.

## MFA modes and PAM

| `pam_mfa_mode` | `AuthenticationMethods` | PAM |
|:---|:---|:---|
| `totp` | `publickey,keyboard-interactive` | google-authenticator required |
| `fido_totp` | same | same (FIDO is first factor only) |
| `fido_only` | `publickey` | **No TOTP prompt** — only if `pam_fido_only_waiver: true` AND `pam_require_fido_pubkey: true` |

Implement `fido_only` via `templates/sshd_config.j2` conditional on mode + waiver. Preflight MUST fail `fido_only` without waiver.

**Default rollout:** `pam_mfa_mode: fido_totp` + `pam_require_fido_pubkey: true` in `prod.yml.example`; lab stays `totp` + `require_fido: false`.

## JIT + certificates

When operator has `valid_from` / `valid_until`:

```bash
# sign-operator-cert-jit.sh.example
ssh-keygen -s "$CA" -I "$name@example.com" -n "$name" \
  -V "${valid_from}:${valid_until}" "$sk_pubkey"
```

Certificate line in `authorized_keys.j2` unchanged. After `jit_purge`, cert and account removed as today.

## Preflight helper

`scripts/preflight-fido-key.py` — stdin: pubkey line or cert path; exit 0 if FIDO-sk backed.

Ansible `preflight_cso.yml` invokes via `ansible.builtin.command` with `changed_when: false` per operator when `pam_require_fido_pubkey`.

## Lab FIDO fixture (optional)

`PAM_FIDO_LAB=1 ./scripts/dev-up.sh`:

1. If host has FIDO/sk support: `ssh-keygen -t ed25519-sk -O verify-required -f lab/keys/engineer-fido.lab -N ""`
2. Else: document skip + use software key only in CI (preflight disabled in dev).

Add `group_vars/dev/fido_lab.yml` merged in `operators_merge.yml`.

## Compliance verify

New check `fido_pubkey` when env `PAM_REQUIRE_FIDO_PUBKEY=1` or reading deployed ansible vars file on host if present:

- Parse `podman exec ssh_pam cat /etc/ssh-pam/operators/*/authorized_keys` or mounted operator configs
- Fail if any prod operator lacks sk prefix (best-effort list from `OPERATORS_HOME`)

## Security notes

- `verify-required` MUST be documented — without it, sk key may work without touch/PIN.
- `fido_only` reduces defense-in-depth — CSO waiver + annual review.
- Stolen laptop with unlocked session ≠ stolen key; still require screen lock policy (organizational).

## Compatibility

- OpenSSH in Alpine 3.19 image: verify `openssh` package supports sk host keys (client keys are on operator workstation).
- macOS/Linux/Windows OpenSSH clients for operators — document minimum versions (OpenSSH 8.2+ sk, 8.4+ ed25519-sk).
