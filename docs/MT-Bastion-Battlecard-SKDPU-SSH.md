# Battlecard: MT «МТ Доступ» SSH vs СКДПУ SSH

| Критерий | СКДПУ «Шлюз SSH» | MT: Bastion Free (v1.0) |
|:---|:---|:---|
| Запись сессии на target | ✅ | ✅ gateway PTY log + hash |
| Credential broking | ✅ | ✅ Ansible Vault / HashiCorp |
| Live moderation | ✅ | ✅ `bastion-session-watch` |
| Session kill | ✅ | ✅ `bastion-session-ctl` |
| MFA | ✅ | ✅ TOTP strict |
| Security-as-a-Code | ⚠️ | ✅ Git/Ansible |
| Air Gap | ✅ | ✅ immutable image |
| ФСТЭК / реестр | ✅ | ❌ org track |
| RDP/Windows | ✅ | ❌ **SSH-only product line** |
| Video replay UI | ✅ | ❌ TTY + hash |

**Pitch:** «Тот же SSH PAM контур для Linux — без vendor lock-in, с Git policy и Air Gap.»

---

*MT Global — Battlecard v1.0*
