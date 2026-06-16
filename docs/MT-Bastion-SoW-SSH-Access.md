# MT: Bastion / «МТ Доступ» SSH — формулировка для договора

Инженеры подрядчика получают доступ к согласованному перечню Linux-серверов **исключительно** через шлюз MT: Bastion (Security-as-a-Code). Интерактивные сессии поддержки выполняются в режиме **SSH gateway** с записью TTY на инфраструктуре Заказчика, MFA, JIT-окнами и audit trail (SHA-256 sidecar).

Заказчик вправе просматривать активные сессии (`bastion-session-watch`) и принудительно завершать их (`bastion-session-ctl kill`).

---

*MT Global — SoW snippet v1.0*
