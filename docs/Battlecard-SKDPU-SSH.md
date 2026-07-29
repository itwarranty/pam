# Battlecard: SSH PAM vs СКДПУ SSH

| Критерий | СКДПУ «Шлюз SSH» | SSH PAM open-source (v1.1) |
|:---|:---|:---|
| Запись сессии на target | ✅ | ✅ gateway PTY log + hash |
| Credential broking | ✅ | ✅ Ansible Vault / HashiCorp |
| Live moderation | ✅ | ✅ `pam-session-watch` |
| Session kill | ✅ | ✅ `pam-session-ctl` |
| MFA | ✅ | ✅ TOTP strict + **FIDO-sk (Tier 5)** |
| FIDO2 / platform key | ✅ | ✅ `ed25519-sk` (no tsh client) |
| Security-as-a-Code | ⚠️ | ✅ Git/Ansible |
| Air Gap | ✅ | ✅ immutable image |
| ФСТЭК / реестр | ✅ | ❌ org track |
| RDP/Windows | ✅ | ❌ **SSH-only product line** |
| Video replay UI | ✅ | ❌ TTY + hash |

**Pitch:** «Тот же SSH PAM контур для Linux — без vendor lock-in, с Git policy и Air Gap.»

---

* Battlecard v1.1*
