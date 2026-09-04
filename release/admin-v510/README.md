# Live Connect Admin V5.10.0

## Equipe e permissões
- Proprietário pode criar contas para funcionários diretamente no Admin.
- Perfis disponíveis: Comercial, Secretaria, Diretoria, Administração e Somente consulta.
- Permissões granulares por usuário:
  - visualizar / editar alunos
  - visualizar / editar / excluir-restaurar financeiro
  - relatórios
  - campanhas
  - chat interno
  - integrações
- Conta principal permanece protegida e com acesso total.

## Financeiro do proprietário
- Nova área independente do Financeiro operacional da Secretaria.
- Resumo do mês: recebido, pendente e exclusões auditadas.
- Lista consolidada de pagamentos por aluno e curso.
- Criar movimentação manual.
- Editar valor, tipo, método, status, vencimento, data de pagamento e observação.
- Excluir e restaurar movimentações.
- Exclusão é lógica/auditada: o registro não é destruído fisicamente.
- Histórico de alterações mostra usuário, ação, observação e data.

## Mensageiro
- Nova mensagem pode abrir automaticamente a janela flutuante.
- Alerta sonoro configurável.
- Notificação do sistema via Web Notifications; o navegador exige autorização explícita do usuário.
- Botões 🔔 e 🔊 no cabeçalho do chat.
- Badge da aplicação é atualizado quando o navegador oferece suporte.

## Deploy
- Backend já aplicado no Supabase Live Connect Comercial.
- Edge Function `school-admin-users` ativa.
- Admin V5.10.0 deve ser publicado manualmente no Cloudflare.
- Portal V5.9.0 permanece compatível; não precisa de novo deploy para esta release.
