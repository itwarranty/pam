## 1. OpenSpec & Documentation

- [x] 1.1 Initialize OpenSpec in `mt-bastion/` and create change `ssh-user-ca-qa-mtglobal`.
- [x] 1.2 Remove duplicate docs/spec stubs; OpenSpec is the single source.
- [x] 1.3 Link OpenSpec change from `docs/MT-Bastion-Whitepaper.md` Policy Gate item 12.

## 2. QA Configuration

- [x] 2.1 Document QA vars and inventory in `design.md` (QA configuration section).
- [ ] 2.2 Create `group_vars/qa_mtglobal.yml` and `inventory/qa-mtglobal.yml` when CA access is granted.

## 3. PKI Artifacts (blocked on org CA access)

- [ ] 3.1 Obtain `mtglobal.team-user-ca.pub` from PKI owner.
- [ ] 3.2 Place pubkey in `lab/ca/mtglobal.team-user-ca.pub`.
- [ ] 3.3 Document private CA custody (HSM/offline) in CSO runbook — see Open Questions in design.md.

## 4. Certificate Issuance (QA)

- [ ] 4.1 Generate operator keypairs locally (`~/.ssh/mt-bastion-qa`).
- [ ] 4.2 Sign certs with `ssh-keygen -s` per `bastion-ssh-user-cert-operators` spec.
- [ ] 4.3 Copy `*-cert.pub` to `lab/certs/` and update `group_vars/qa_mtglobal.yml`.

## 5. Deploy & Verify

- [ ] 5.1 Enable `bastion_trusted_user_ca_file` in `group_vars/qa_mtglobal.yml`.
- [ ] 5.2 Run `ansible-playbook -i inventory/qa-mtglobal.yml site.yml` on Rocky 9 QA host.
- [ ] 5.3 Execute acceptance scenarios from `bastion-ssh-ca-qa-acceptance` spec.
- [ ] 5.4 Update `docs/CSO-Demo-Runbook.md` with CA demo block (optional).

## 6. Prod Readiness (post-QA)

- [ ] 6.1 CSO sign-off on validity period and cert renewal SOP.
- [ ] 6.2 Move CA pubkey sourcing to Vault; remove certs from git workflow.
- [ ] 6.3 Archive OpenSpec change and merge specs into `openspec/specs/` when complete.
