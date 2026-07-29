# ITWarranty SSH PAM

Open-source **SSH access gateway** for support engineers: who connected, when, where, what they did — with MFA, short-lived access, and session logs.

Built for Rocky Linux 9, Air Gap / regulated networks. **Apache-2.0.**

**Repo:** [github.com/itwarranty/pam](https://github.com/itwarranty/pam)

## Try in one command

```bash
git clone git@github.com:itwarranty/pam.git
cd pam
./scripts/pam up
```

Needs Lima + Ansible (macOS: `brew install lima podman ansible`). First run can take 10–20 minutes.

Then:

```bash
./scripts/pam doctor gateway-lab
./scripts/pam doctor engineer-jump
```

## Day-to-day commands

```bash
./scripts/pam help
./scripts/pam verify              # health / compliance
./scripts/pam sessions list
./scripts/pam sessions kill <id>
./scripts/pam access grant bob --pam --apply
```

## What you get

| Need | How |
| :--- | :--- |
| Jump to a host | `access: jump` + whitelist |
| Full session recording on target | `access: gateway` |
| Four-eyes on the gateway | `access: shell` |
| Read-only auditor | `access: audit` |
| MFA | SSH key + TOTP (optional FIDO) |
| Revoke access | Remove from config, re-run playbook |

Only **SSH**. Not RDP / web / databases — by design.

## Prod deploy (short)

1. Rocky Linux 9, SELinux Enforcing, rootless Podman  
2. `./trusted_download.sh` → copy image into Air Gap  
3. Fill `pam_operators` / `pam_targets` (Vault)  
4. `ansible-playbook -i inventory/hosts.yml site.yml -e @group_vars/profiles/prod.yml`

Profiles: `group_vars/profiles/{eval,pilot,prod}.yml`

## Docs

| Doc | For |
| :--- | :--- |
| [Runbooks](docs/Runbooks.md) | Fix “cannot login”, revoke, kill session |
| [CSO Demo](docs/CSO-Demo-Runbook.md) | 10‑minute demo |
| [Whitepaper](docs/Whitepaper.md) | Security controls |
| [Overview](docs/SSH-PAM-Overview.md) | Customer pitch |
| [FIDO](docs/FIDO-Onboarding.md) | Hardware keys |

Vs commercial SSH gateways: [Battlecard](docs/Battlecard-SKDPU-SSH.md)

## Need help at a customer site?

ITWarranty can deploy, harden, and support this in production — or discuss commercial multi-protocol PAM.

→ [github.com/itwarranty](https://github.com/itwarranty)

## License

Apache License 2.0 — see [LICENSE](LICENSE).
