# DR module contract (PAM ↔ ITWarranty DR)

DR inventory runs on a **separate host/repo** (`itwarranty/DR`). PAM provisions the jump path; DR consumes it read-only after human sessions.

## PAM-side variables (authoritative)

Enable in PAM `group_vars`:

```yaml
pam_dr_enabled: true
pam_dr_service_operator_name: dr-scanner
pam_dr_jit_window_minutes: 15
```

Lab fixture: `group_vars/dev/dr_service_lab.yml`.

Runtime paths (defaults from `group_vars/all.yml`):

| Variable | Default |
| :--- | :--- |
| `pam_user` | `pam` |
| `pam_home` | `/home/pam` |
| `pam_targets_home` | `/home/pam/targets` |
| `audit_log_dir` | `/var/log/pam_sessions` |
| `pam_container_name` | `ssh_pam` |

JIT sync tag on PAM host:

```bash
ansible-playbook -i inventory/local-lima.yml site.yml --tags dr_jit_sync
```

## DR-side mapping (v2.1+)

DR Ansible accepts **`pam_*` names**; legacy `bastion_*` aliases remain for older playbooks.

| DR / legacy | PAM product |
| :--- | :--- |
| `bastion_user` | `pam_user` |
| `bastion_home` | `pam_home` |
| `bastion_targets_home` | `pam_targets_home` |
| `bastion_ssh_port` | PAM publish port (2222) |
| `audit_log_dir` | `/var/log/pam_sessions` |
| `bastion_dr_enabled` | `pam_dr_enabled` |
| `bastion_dr_jit_window_minutes` | `pam_dr_jit_window_minutes` |

Shell scripts honour `PAM_USER`, `PAM_HOME`, `PAM_CONTAINER_NAME`, `PAM_TARGETS_HOME`, `PAM_AUDIT_LOG_DIR` with `BASTION_*` fallbacks.

## Lima lab (current)

PAM VM: `pam-prod` (`./scripts/dev-up.sh` from `pam/` repo).

```bash
# PAM deploy (Mac host)
cd pam && ansible-playbook -i inventory/local-lima.yml site.yml

# DR integration (after PAM + DR enabled)
cd ../DR && LIMA_INSTANCE_NAME=pam-prod ./scripts/test-integration.sh
```

## Out of scope

- DR does **not** read target broked identity files (v2 service operator).
- RISK pre-auth is **not** wired in PAM v1.2.0 — see [Integrations](./Integrations.md).

Spec: [pam-dr-service-operator](../openspec/specs/pam-dr-service-operator/spec.md)
