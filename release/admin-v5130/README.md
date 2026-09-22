# Admin Live Connect V5.13.0 — chat por atividade + tarefas com cobrança

Base: V5.12.3.

## Conversas

- A lista passa a usar `school_chat_conversations_v2`.
- Conversas são ordenadas por `last_message_at DESC`: a atividade mais recente sobe automaticamente.
- Mensagens novas não trocam a conversa ativa nem abrem o chat à força.
- Dentro da conversa, o histórico mantém o padrão natural: antigas acima, novas abaixo.
- Push de mensagem visível atualiza a lista e sinaliza a chegada sem roubar o foco.

## Tarefas criadas a partir de mensagens

O fluxo antigo baseado em `prompt()` foi substituído por formulário próprio com:

- título;
- responsável;
- prioridade: normal, alta ou urgente;
- prazo obrigatório;
- primeiro lembrete;
- intervalo de repetição enquanto estiver atrasada.

A tarefa mantém vínculo com a mensagem de origem.

### Responsabilidade

- Uma tarefa atribuída permanece destacada para o responsável até ser concluída.
- Tarefas atrasadas recebem destaque visual.
- O responsável pode concluir, mas não pode cancelar a própria tarefa.
- Cancelamento/reabertura é reservado ao criador ou proprietário.
- Criação, conclusão, cancelamento e reabertura ficam auditados.

## Lembretes

Migration em produção:

`20260922113842_chat_task_accountability_and_reminders`

Edge Function ativa:

`school-task-reminders`

Cron:

`school-task-reminders-every-minute` — executa a cada minuto.

O cron chama a Edge Function com segredo mantido no Supabase Vault. A Edge Function envia Web Push somente ao responsável da tarefa e repete lembretes após o vencimento conforme a cadência configurada até a tarefa deixar de estar pendente.

## Validação

- ciclo criar → bloquear cancelamento pelo responsável → concluir validado em transação com rollback;
- nenhuma tarefa de teste persistiu;
- `school_chat_conversations_v2` validado em ordem decrescente de última mensagem;
- RPCs de usuário: `authenticated` permitido e `anon` negado;
- RPC de claim de lembrete: somente `service_role`;
- Cron ativo;
- respostas do pg_net/Edge Function confirmadas com HTTP 200;
- JavaScript validado com `node --check`;
- `build.json` válido;
- assets principais servidos localmente com HTTP 200;
- ZIP completo validado com `unzip -t`.

Cache-bust: `5130`.

Publicar o pacote completo de Static Assets; não fazer deploy parcial.
