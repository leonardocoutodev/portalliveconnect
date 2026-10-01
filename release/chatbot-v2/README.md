# Lico Chatbot v2 — Site Live Connect

Data de publicação: 2026-10-01

## Produção

Edge Function: `portal-commercial-chat`
Versão Supabase: 18
Bot version: `liveconnect-router-2.0`

## Principais mudanças

- roteamento de intenção antes do funil comercial;
- suporte dedicado para acesso EAD/portal do aluno;
- suporte financeiro para aluno existente;
- suporte acadêmico para notas, módulos, materiais e certificado;
- fluxo separado para Jovem Aprendiz;
- fast path de preço: responde valor quando o curso é identificado;
- handoff humano com resumo, assunto e próxima ação;
- notificações de handoff para o operacional;
- preenchimento de `qualification_completed_at`, `close_probability`, `primary_objection` e `next_best_action`;
- memória de visitante reativada;
- eventos de intenção e conversão registrados em `lico_learning_events`;
- abertura do chatbot agora comunica também suporte a alunos;
- catálogo, cursos e preços continuam vindo do Supabase como fonte de verdade.

## Runtime

`memory_enabled = true`
`learning_enabled = true`
`session_idle_minutes = 30`

## Segurança e arquitetura

- o frontend continua chamando o mesmo endpoint;
- nenhuma service role foi exposta ao navegador;
- a função segue executando acesso privilegiado somente no servidor;
- origens do site permanecem restritas pela função;
- dados comerciais continuam centralizados no Supabase Live Connect.

## Observação sobre IA generativa

Esta release melhora compreensão por roteamento semântico/regras e ferramentas do próprio backend. Ela não depende de um provedor LLM externo para funcionar. Um provedor generativo pode ser adicionado depois como camada opcional, mantendo cursos, preços e dados reais sob controle do Supabase.
