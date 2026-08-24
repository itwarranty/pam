# Integrations and adjacent products

What is wired into the SSH PAM **runtime** today vs documented contracts for separate modules.

## ITWarranty DR (Disaster Recovery)

DR is a **separate module** that talks to PAM through a documented contract:

- Service operator `dr-scanner` (`pam_dr_service_operator_name`) with `access: jump` and JIT `permit_open`
- Ansible tag `dr_jit_sync` updates DR scanner permit windows
- PAM runtime paths use `pam_user` / `pam_home` (default `pam`, `/home/pam`) — current product naming only

DR does not ship inside the PAM container. Deploy DR on its own host/repo and point it at the PAM inventory contract your environment uses.

## ITWarranty RISK (pre-auth gate)

RISK is a **separate product module** (repository `itwarranty/RISK`) for pre-authentication risk scoring from local threat feeds.

**Not integrated into PAM runtime yet.** PAM does not call RISK during SSH authentication in v1.2.0. Future integration will be an explicit pre-auth hook documented in both products; until then, do not assume RISK blocks logins on the gateway.

## OIDC / SAML

PAM Tier 4 includes **certificate-signing tooling and examples**, not a runtime IdP inside the gateway:

- `scripts/sign-operator-cert-oidc.sh.example` — sign SSH user certs after OIDC group check
- `scripts/sign-operator-cert-saml.sh.example` — SAML→OIDC bridge pattern
- `pam_oidc_cert_policy_enabled` — preflight requires operator **certificates**, not raw pubkeys

The gateway container does **not** terminate OIDC/SAML browser flows. Your org IdP remains external; PAM consumes the resulting SSH user certificates.

## Related docs

- [Whitepaper](./Whitepaper.md) — security controls and OIDC section
- [DR service operator spec](../openspec/specs/pam-dr-service-operator/spec.md)
- RISK module: `itwarranty/RISK` — `docs/PAM-integration.md`
