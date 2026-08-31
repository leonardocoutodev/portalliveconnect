# KingHost payment frontend patch

This patch accompanies the 31/08/2026 payment/Ouro reliability fix.

Frontend changes:
- paid enrollment requires e-mail in step 1;
- e-mail is sent in the enrollment payload;
- friendly messages for missing/invalid e-mail;
- Profissão Rápida payment label is human-readable;
- copy reflects automatic enrollment after payment;
- app dynamically imports forms.js with a payment-fix cache key.

Production package is generated separately as a full www folder for KingHost/IIS.
