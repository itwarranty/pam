# HA active-passive (SSH PAM)

## Topology

- **Primary:** `ssh_bastion` running, accepts SSH :2222.
- **Standby:** container stopped; same Ansible config; `bastion_ha_role: standby`.
- **Shared storage:** NFS/WORM mount for `audit_log_dir` (mandatory for log continuity).

## Failover

1. Stop primary (maintenance / failure).
2. Promote standby: `./scripts/bastion-ha-promote.sh`
3. Move VIP/DNS to standby IP.
4. Operators reconnect — **active sessions lost** (documented limitation).

## Limitations

- Session registry (`runtime/sessions/`) **not replicated** — kill/list on promoted node only sees new sessions.
- No automatic Pacemaker — manual or client-added STONITH.
- Split-brain: use single VIP; do not run two primaries with same operators.

## Ansible

- `inventory/ha-cluster.yml.example`
- `group_vars/ha.yml.example`
- `bastion_ha_enabled: true`

---

* HA Runbook v1.0*
