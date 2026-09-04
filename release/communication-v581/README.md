# Live Connect V5.8.1 — Lico + Chat Interno Flutuante

## Lico

O assistente comercial passa a se chamar **Lico** e usa qualificação contextual antes de liberar a matrícula.

Regras principais:
- nome e sobrenome válidos são obrigatórios; respostas genéricas ou inválidas não avançam o fluxo;
- identifica se o curso é para a própria pessoa, filho(a), neto(a), irmão/irmã, cônjuge ou terceiro;
- diferencia idade do contato e idade do aluno;
- menores de 18 anos exigem responsável legal antes do fechamento;
- pergunta se estuda, etapa escolar e turno quando aplicável;
- pergunta se trabalha, ocupação e horário; se não trabalha, identifica experiência anterior quando pertinente;
- jovens de 14 a 18 anos sem experiência profissional recebem perguntas sobre primeiro emprego, currículo, descoberta profissional e Jovem Aprendiz, sem enquadramento incoerente de mudança de carreira;
- coleta disponibilidade e cruza com turmas/vagas reais;
- presencial noturno é exclusivamente quarta-feira, 18:00–20:00 e exige confirmação antes da matrícula;
- coleta objetivo, prazo para começar, fator de decisão, autoridade para matrícula, curso e e-mail;
- mantém score de qualificação e grava resumo no CRM;
- preserva status de leads já existentes e nunca rebaixa matrícula confirmada;
- ao concluir, gera CTA para matrícula e o Portal reaproveita os dados coletados e a turma compatível.

## Chat interno do Admin

- canais Geral, Comercial, Secretaria e Diretoria;
- janela flutuante persistente independentemente da área do Admin aberta;
- polling de mensagens e contador de não lidas;
- nova mensagem abre automaticamente a janela e leva ao canal com novidade;
- o proprietário/master continua master no sistema, porém **aparece como Comercial somente no chat interno**;
- histórico e envio continuam protegidos pelas permissões de staff.

## Backend

Aplicado diretamente no Supabase **Live Connect Comercial** (`utfxjadpntvbrhnkghbf`).

Edge Function `portal-commercial-chat` publicada e validada em produção.

## Deploy manual

- **Admin:** pacote completo V5.8.1 → Cloudflare, manualmente.
- **Portal:** pacote V5.8.1 → KingHost, manualmente.
- **GitHub:** versionamento/histórico; commit não representa deploy do Portal ou Admin.

Não usar os pacotes V5.7.0 depois desta release.