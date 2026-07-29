# Runbooks (short)

Practical fixes. Deep theory: [Whitepaper](./Whitepaper.md), demo: [CSO-Demo-Runbook](./CSO-Demo-Runbook.md).

## Engineer cannot log in

1. `./scripts/pam doctor <operator>` — key present? TOTP? role?
2. Port open? `nc -z <host> 2222`
3. Wrong role:
   - **jump** — use ProxyJump (`-J`), not interactive shell
   - **gateway** — SSH to gateway, then pick target
4. MFA: enter 6-digit TOTP immediately (30s window)
5. Revoked? Operator must be in `pam_operators` and playbook re-applied

## Revoke access

1. Remove operator from `pam_operators` (or `group_vars/dev/test_operators.yml` in lab)
2. `ansible-playbook -i <inventory> site.yml`  
   or `./scripts/pam access revoke <name> --apply`
3. Confirm: SSH with old key fails; home under operators gone

## Kill an active gateway session

On the gateway host:

```bash
./scripts/pam sessions list
./scripts/pam sessions kill <session-id>
```

Or Ansible:  
`ansible-playbook -i <inventory> site.yml --tags session_kill -e pam_session_kill_id=<id>`

## Break-glass

Only if enabled in config (`break_glass: true` + short JIT window + `incident_id`).  
After use: revoke and keep the incident ticket. Details: Troubleshooting-Workflow § break-glass.

## Compliance failed

```bash
./scripts/pam verify
./scripts/pam verify --json
```

Typical fixes:

| Check | What to do |
| :--- | :--- |
| OS / arch | Use Rocky Linux 9 x86_64 |
| SELinux | `setenforce 1` and persist Enforcing |
| container | Start `ssh_pam` as user `pam` |
| mfa_label | Rebuild with `./trusted_download.sh` (MFA_STRICT=1) |
| operators empty | Fill `pam_operators` and redeploy |

## Lab from zero

```bash
./scripts/pam up
```
