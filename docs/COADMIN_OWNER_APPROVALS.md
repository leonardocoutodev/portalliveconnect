# Coadministrador com aprovação do proprietário

## Modelo

- `master_admin`: proprietário protegido.
- `coadmin`: acesso amplo às áreas Master, Secretaria, Comercial e Diretoria.
- O coadministrador não pode alterar, desativar, rebaixar ou remover o perfil proprietário.
- Ações críticas do coadministrador são registradas em `admin_approval_requests` e exigem decisão do proprietário.

## Ações críticas cobertas

- Alterações de acessos e perfis.
- Exclusão definitiva de lead.
- Campanhas que substituem oferta pública ou alteram precificação.
- Ativação/pausa de campanha pública vinculada a preço.
- Escritas diretas em `pricing_versions`, `site_settings` e `contract_templates`.

## Fluxo

1. O coadministrador inicia a ação.
2. O banco cria uma solicitação `pending` e não aplica a mudança crítica.
3. O proprietário visualiza a fila em **Master > Aprovações**.
4. Ao aprovar, a operação é executada e auditada.
5. Ao rejeitar, nada é alterado e a decisão fica registrada.

## Proteções

- Trigger de banco protege o perfil proprietário independentemente da interface.
- RLS da fila permite leitura apenas ao solicitante e ao proprietário.
- Funções de decisão são restritas ao proprietário.
- Operações sensíveis são auditadas.
