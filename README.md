# MT: Bastion

Security-as-a-Code jump host for Rocky Linux 9 (Rootless Podman, CSO Policy Gate).

## Quick start (dev)

```bash
./scripts/dev-up.sh
```

## Documentation

- [Engineer Onboarding](docs/Engineer-Onboarding.md) — доступ к repo + первый dev-стенд
- [Whitepaper](docs/MT-Bastion-Whitepaper.md)
- [CSO Demo Runbook](docs/CSO-Demo-Runbook.md)
- [OpenSpec: SSH User CA QA](openspec/changes/ssh-user-ca-qa-mtglobal/)

## Prod deploy

Fill `bastion_operators` in `group_vars/all.yml` (Vault). Run `ansible-playbook site.yml`.
