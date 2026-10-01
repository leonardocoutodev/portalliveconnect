# Lico Chatbot v2.1 — Atendimento humano via WhatsApp

Data: 2026-10-01

## Produção

- Edge Function: `portal-commercial-chat`
- Supabase version: 19
- Bot version: `liveconnect-router-2.1`
- WhatsApp oficial: `+55 73 3223-7593`
- Base: `https://wa.me/557332237593`

## Mudanças

- Lico passa a sugerir atendimento humano em pontos de dúvida, objeção e suporte.
- Pedido explícito por atendente gera handoff e link direto para o WhatsApp.
- Handoffs de acesso EAD, financeiro e suporte acadêmico incluem CTA para WhatsApp.
- O link usa mensagem pré-preenchida conforme o assunto da conversa.
- A API retorna também `whatsapp_url` e `actions[]` para permitir renderização de botão pelo frontend.
- O número utilizado confere com `site_settings.whatsapp` no Supabase.

## Segurança

Nenhuma credencial nova foi adicionada ao frontend. O link de WhatsApp contém apenas o número público e uma mensagem de atendimento.
