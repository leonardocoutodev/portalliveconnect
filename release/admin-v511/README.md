# Live Connect Admin V5.11.0

## Central de Comunicação
- painel consolidado de mensagens não lidas, tarefas e atendimentos prioritários;
- chat flutuante global em qualquer tela;
- presença online/ausente e “digitando…”;
- confirmações de leitura;
- @Todos / @Comercial / @Secretaria / @Diretoria;
- busca, mensagens fixadas e tarefas;
- anexos privados de até 10 MB;
- vínculo de mensagem com lead, matrícula ou contrato.

## Web Push
- Service Worker no Admin;
- assinatura Push por usuário/dispositivo;
- chave VAPID privada gerada no servidor e armazenada no Supabase Vault;
- nenhuma chave privada é incluída no ZIP ou no GitHub;
- Edge Function `school-chat-push` envia notificações aos destinatários do canal respeitando canais privados e permissões;
- o primeiro clique em 🔔 solicita permissão do navegador e registra o dispositivo.

## Lico
- insight de probabilidade estimada de fechamento;
- objeção principal;
- próxima melhor ação;
- resumo de handoff para o Comercial;
- follow-up automático quando o lead pede humano;
- follow-up automático após sessão expirada para leads quentes/mornos;
- follow-ups do Lico são concluídos quando o atendimento é marcado como ganho.

## Operação
- Backend V5.11.0 já aplicado no Supabase Live Connect Comercial.
- Admin deve ser publicado manualmente no Cloudflare.
- Portal não precisa de novo deploy por causa desta release.
- Cache-bust do Admin: `v=5110`.
