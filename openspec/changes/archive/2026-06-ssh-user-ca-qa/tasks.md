## 1. OpenSpec & Documentation

- [x] 1.1 Initialize OpenSpec in `bastion/` and create change `ssh-user-ca-qa`.
- [x] 1.2 Remove duplicate docs/spec stubs; OpenSpec is the single source.
- [x] 1.3 Link OpenSpec change from `docs/Whitepaper.md` Policy Gate item 12.

## 2. QA Configuration

- [x] 2.1 Document QA vars and inventory in `design.md` (QA configuration section).
- [x] 2.2 Create `group_vars/qa.yml.example` and `inventory/qa.yml.example` (copy when CA access granted).

## 3. PKI Artifacts (blocked on org CA access)

- [ ] 3.1 Obtain `user-ca.pub` from PKI owner.
- [ ] 3.2 Place pubkey in `lab/ca/user-ca.pub`.
- [x] 3.3 Document private CA custody (HSM/offline) — `scripts/sign-operator-cert.sh.example`, Whitepaper §7.

## 4. Certificate Issuance (QA)

- [x] 4.1 Generate operator keypairs locally (`~/.ssh/bastion-qa`) — documented in design.md.
- [x] 4.2 Sign certs with `ssh-keygen -s` — `scripts/sign-operator-cert.sh.example`.
- [ ] 4.3 Copy `*-cert.pub` to `lab/certs/` and update `group_vars/qa.yml` (requires live CA).

## 5. Deploy & Verify

- [x] 5.1 Enable `bastion_trusted_user_ca_file` — documented in `qa.yml.example`.
- [ ] 5.2 Run `ansible-playbook -i inventory/qa.yml site.yml` on Rocky 9 QA host.
- [ ] 5.3 Execute acceptance scenarios from `bastion-ssh-ca-qa-acceptance` spec.
- [x] 5.4 Update `docs/CSO-Demo-Runbook.md` with CA demo block (optional).

## 6. Prod Readiness (post-QA)

- [x] 6.1 CSO sign-off on validity period and cert renewal SOP — Whitepaper §7.
- [ ] 6.2 Move CA pubkey sourcing to Vault; remove certs from git workflow.
- [x] 6.3 Archive OpenSpec change and merge specs into `openspec/specs/`.
