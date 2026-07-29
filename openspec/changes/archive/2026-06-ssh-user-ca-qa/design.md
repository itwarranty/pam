## Context

SSH PAM runs OpenSSH in a Rootless Podman container on Rocky Linux 9. Operators are provisioned via Ansible (`pam_operators`) into mounted home directories. Authentication is `publickey + keyboard-interactive (TOTP)`.

Lab (`group_vars/local_lima.yml`) uses raw ed25519 pubkeys with comments `*@example.com`. QA will add org SSH User CA so operators present short-lived **user certificates** signed by `example.com` User CA private key (held offline/HSM, never on the gateway).

Implementation hooks already exist:
- `pam_trusted_user_ca_file` → copies CA `.pub`, mounts into container, sets `TrustedUserCAKeys`.
- `operator.certificate` → written to `authorized_keys` via `templates/authorized_keys.j2`.
- Jump operators retain `restrict,port-forwarding,permitopen=...` in authorized_keys.

## Goals / Non-Goals

**Goals:**
- QA-ready spec for enabling CA when PKI access is granted.
- Clear artifact layout (`lab/ca/`, `lab/certs/`, Vault in prod).
- Acceptance tests CSO can observe on demo.
- Rollback to raw pubkeys without image rebuild.

**Non-Goals:**
- Building internal PKI/HSM in this change.
- Removing raw-key lab path before QA pass.
- DNS-based auth (domain signing ≠ SSH User CA).

## Decisions

### D1: CA public key only on the gateway

**Decision:** Only `user-ca.pub` is deployed to gateway; private CA never touches gateway host or container.

**Rationale:** Standard SSH CA model; aligns with CSO supply-chain and key custody.

### D2: Certificate identity convention

**Decision:**
- Unix account: `engineer-jump` (match `operator.name`)
- Key ID (`ssh-keygen -I`): `engineer-jump@example.com`
- Principal (`-n`): `engineer-jump`
- Email field in Ansible: `engineer-jump@example.com`

**Rationale:** Consistent with lab keys and TOTP otpauth labels.

### D3: Validity periods

| Environment | Recommended validity |
|:---|:---|
| QA | 7–30 days (`-V +30d`) |
| Prod | 24–72 hours (CSO approval required) |

**Rationale:** Short-lived certs limit compromise blast radius; QA may use longer windows for operational ease.

### D4: Restrictions in Ansible, not in cert extensions (default)

**Decision:** Jump/shell enforcement stays in `sshd_config.j2` and `authorized_keys.j2` (`restrict`, `ForceCommand`). Cert extensions optional only for `source-address` if CSO requires.

**Rationale:** Single declarative source (Ansible); avoids duplicating policy in PKI and playbooks.

### D5: MFA unchanged

**Decision:** `AuthenticationMethods publickey,keyboard-interactive` applies to certificate-based pubkey equally.

**Rationale:** CA replaces long-lived keys, not second factor.

## Rollback

1. Remove or comment `pam_trusted_user_ca_file`.
2. Switch operators from `certificate` to `pubkey` in group vars.
3. Re-run `ansible-playbook site.yml`.

No container image rebuild required.

## Risks / Trade-offs

| Risk | Mitigation |
|:---|:---|
| CA private key leak | Offline/HSM, break-glass procedure, CA rotation runbook |
| Expired certs lock out operators | QA calendar + renewal SOP; prod automation later |
| QA delays block lab | Lab stays on raw keys (`local_lima`); CA is opt-in via `qa` group |

## Open Questions

- [ ] Who operates User CA private key at  (role, HSM)?
- [ ] Prod: manual signing vs automated step-ca/Vault PKI?
- [ ] Required `source-address` restrictions for operator certs?

## QA configuration (copy when CA is available)

Create `group_vars/qa.yml`:

```yaml
pam_lab_domain: example.com
pam_trusted_user_ca_file: "{{ playbook_dir }}/lab/ca/user-ca.pub"

pam_operators:
  - name: engineer-jump
    email: engineer-jump@example.com
    certificate: "{{ lookup('file', playbook_dir + '/lab/certs/engineer-jump-cert.pub') }}"
    mfa_secret: "{{ vault_engineer_jump_mfa }}"
    access: jump
    permit_open:
      - "10.0.1.10:22"
```

Create `inventory/qa.yml`:

```yaml
all:
  children:
    pam_servers:
      children:
        qa:
          hosts:
            gateway-qa.example.com:
              ansible_host: 10.0.0.50
              ansible_user: ansible
```

Deploy: `ansible-playbook -i inventory/qa.yml site.yml`
