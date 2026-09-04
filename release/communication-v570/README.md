# Live Connect V5.7.0 — Comunicação e Chatbot Comercial

## Admin
- Chat interno com canais Geral, Comercial, Secretaria e Diretoria.
- Histórico por canal e contagem de não lidas.
- Caixa de entrada do Chatbot Comercial dentro do Admin.
- Score, estágio, curso de interesse, status e responsável.
- Comercial pode assumir a conversa, responder, devolver ao bot e marcar como qualificado/fechamento/matrícula fechada/perdido/encerrado.

## Chatbot público
- Widget flutuante nas páginas públicas.
- Qualificação progressiva por nome, WhatsApp, idade, objetivo e curso.
- Recomenda cursos ativos do banco.
- Consulta a campanha pública vigente antes de informar preço.
- Registra/atualiza lead, interesse e atividade no CRM.
- Encaminha para matrícula no curso escolhido com UTMs.
- Pode transferir a conversa para atendimento humano no Admin.

## Backend
- Migration: `supabase/migrations/20260904173000_school_chat_and_commercial_bot.sql`
- Edge Function: `supabase/functions/portal-commercial-chat/index.ts`

A migration e a Edge Function devem ser aplicadas somente no projeto **Live Connect Comercial**.


## Regra de deploy

- **Portal público:** deploy manual na **KingHost**. O pacote `Live_Connect_PORTAL_PATCH_V5.7.0_CHATBOT_COMERCIAL.zip` deve ser enviado manualmente para a hospedagem do portal.
- **Admin:** deploy manual no **Cloudflare**. O pacote `Live_Connect_ADMIN_V5.7.0_CHAT_INTERNO_CHATBOT_COMERCIAL.zip` deve ser publicado manualmente no Worker/hosting do Admin.
- **Backend Supabase:** migrations e Edge Functions são aplicadas diretamente no projeto **Live Connect Comercial** quando a conexão correta estiver disponível.
- **GitHub:** usado para versionamento e histórico. Commit no repositório não deve ser interpretado como deploy automático do Portal ou do Admin.
