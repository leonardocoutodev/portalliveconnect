# Live Connect V5.8.2 — Lico Comercial + Continuidade de Sessão

## Lico
- Profissão Rápida é apresentada como recomendação principal para quem quer acelerar a formação.
- Alternativa Tradicional permanece disponível com mensalidades via Pix ou dinheiro.
- O Lico consulta a oferta comercial real do curso antes de apresentar valores.
- O Lico explica os cursos em linguagem comercial, usando descrição, duração e carga horária do catálogo quando disponíveis.
- Nenhuma referência a sistemas internos, fornecedores ou bastidores é exposta ao lead.
- Nova pergunta: o lead quer receber uma sugestão de formação?
- Sugestões automáticas usam somente cursos pagos.
- Curso gratuito não é misturado com pago e só é usado como fallback quando o lead deixa claro que a opção gratuita é a única possibilidade.
- Cursos com o mesmo nome em versões paga e gratuita são tratados como produtos distintos; a versão paga tem prioridade.
- A escolha Profissão Rápida x Tradicional é armazenada e reaproveitada na matrícula.

## Continuidade
- Sessões e mensagens já ficam armazenadas no Supabase.
- O token da sessão permanece no navegador.
- Ao retornar ao site no mesmo navegador, o Portal chama `resume`, recupera o histórico e o Lico reconhece o retorno.
- O Lico informa que o atendimento ficou salvo e continua da etapa exata em que parou.
- `resume_count` e `last_resumed_at` registram retomadas de sessão.

## Deploy
- Backend já aplicado no Supabase Live Connect Comercial.
- Edge Function `portal-commercial-chat` ativa.
- Portal V5.8.2: deploy manual na KingHost.
- Admin V5.8.1 permanece compatível; não exige novo deploy apenas para esta atualização.
