# Live Connect Admin V5.11.1

## Auditoria financeira privada
- `school_finance_audit` exige `is_owner() = true`.
- Permissão `view_finance` não concede mais acesso à auditoria.
- Outros funcionários podem continuar usando o financeiro operacional conforme permissões.
- A interface só consulta e exibe a auditoria quando `permissions.owner = true`.
- Para usuários não proprietários, o terceiro indicador financeiro mostra movimentações do período em vez de exclusões auditadas.
- A tabela física `financial_audit_logs` continua sem acesso direto para `authenticated`; leitura é feita somente pela RPC protegida.

## Deploy
- Backend já aplicado no Supabase Live Connect Comercial.
- Admin V5.11.1 deve ser publicado manualmente no Cloudflare para esconder a seção na interface dos demais usuários.
