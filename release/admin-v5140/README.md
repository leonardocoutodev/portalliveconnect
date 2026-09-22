# Admin Live Connect V5.14.0 — Centro Operacional + Aluno 360°

Base: V5.13.0.

## Escopo

A V5.14.0 transforma o Admin de um conjunto de telas em um centro operacional orientado por pendências.

### Centro operacional

- Dashboard universal por permissões.
- Indicadores reais de alunos, matrículas, turmas, Portal/Ouro, contratos, financeiro, tarefas, chat, follow-ups e leads.
- Fila “Hoje” com itens que exigem ação.
- Itens resolvidos deixam de aparecer; itens ativos permanecem mesmo depois de lidos.

### Central de notificações

- Sino no cabeçalho com contador de não lidas.
- Severidade info / warning / danger.
- Notificações derivadas do estado atual da operação, sem tabela duplicando os eventos.
- Estado de leitura é individual por usuário.
- Se o item muda após ter sido lido, volta a ficar não lido.
- Ações abrem diretamente o contexto correspondente.

### Busca global V2

RPC: `school_admin_global_search_v2`.

Pesquisa respeitando as permissões do usuário em:
- aluno / lead;
- nome, CPF, RG, WhatsApp e e-mail;
- curso;
- contrato;
- ID/login Ouro;
- pagamento;
- tarefa.

Resultados de aluno, contrato e Ouro podem abrir diretamente o Aluno 360°.

### Aluno 360°

RPC: `school_student_360`.

Consolida:
- dados cadastrais;
- matrículas e turmas;
- financeiro, quando autorizado;
- contratos;
- fila Portal/EAD;
- integração e ID Ouro;
- estado de credenciais EAD sem retornar a senha persistida;
- alertas operacionais;
- linha do tempo consolidada.

A edição agora respeita `edit_students` em vez de exigir `master_admin`. Isso corrige a inconsistência em que uma Secretaria podia ter permissão de edição mas o RPC bloqueava o salvamento.

## Backend

Migration aplicada em produção:

`20260922121104_admin_v514_operational_center_360_notifications`

Arquivo versionado:

`supabase/migrations/20260922121104_admin_v514_operational_center_360_notifications.sql`

Os novos RPCs expostos ao frontend:
- exigem usuário autenticado;
- validam `is_staff()` e/ou permissões específicas;
- têm EXECUTE revogado de `anon` e `PUBLIC`;
- a tabela privada de estado das notificações não possui SELECT para `anon` ou `authenticated`.

O Security Advisor continua sinalizando os novos RPCs `SECURITY DEFINER` para usuários autenticados. Isso é esperado porque eles precisam consolidar dados protegidos e, no caso das notificações/Aluno 360°, dados em schema privado. O acesso é restringido dentro dos próprios RPCs por perfil/permissão e `anon` está bloqueado.

## Validação

- Secretaria com `edit_students`: atualização de perfil e matrícula validada em transação com rollback.
- Cancelar/restaurar matrícula pela Secretaria validado em rollback.
- Leitura individual de notificações validada em rollback.
- Novos RPCs: `authenticated = EXECUTE`, `anon = sem EXECUTE`.
- Tabela privada de notificações: sem SELECT para `anon` e `authenticated`.
- 11 arquivos JavaScript passaram em `node --check`.
- Referências de assets sem arquivos faltantes.
- index, entry, central, icons, CSS e build servidos localmente com HTTP 200.
- ZIP completo validado com `unzip -t`.
- Cache-bust: `5140`.

## Deploy

Publicar o pacote completo V5.14.0 no mesmo Cloudflare Static Assets do Admin. Não fazer deploy parcial.
