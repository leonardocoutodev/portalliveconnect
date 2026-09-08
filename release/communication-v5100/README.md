# Live Connect V5.10.0 — Lico Conversacional

## Objetivo
Substituir o fluxo rígido de formulário por uma conversa comercial adaptativa.

## Fluxo padrão
1. abertura e identificação da intenção;
2. objetivo/área de interesse;
3. disponibilidade/modalidade;
4. recomendação de formação;
5. apresentação de condição/modalidade comercial quando aplicável;
6. coleta de nome, WhatsApp e e-mail apenas após existir valor/contexto;
7. objeções, fechamento e matrícula.

## Regras críticas
- saudações como “bom dia”, “boa tarde”, “oi” e “olá” nunca são aceitas como nome;
- nome só é persistido quando passa validação específica;
- “me chamo ...”, “meu nome é ...” e “sou ...” são tratados como apresentação;
- pedido de humano, preço e endereço podem interromper o fluxo sem perder contexto;
- cursos gratuitos são priorizados quando o visitante declara explicitamente que gratuito é a única possibilidade;
- idade desconhecida não é interpretada como menor de idade;
- sessões antigas podem ser reiniciadas após upgrade do frontend.

## Produção
O Portal continua com deploy manual na KingHost.
A Edge Function `portal-commercial-chat` foi atualizada no código-fonte do repositório e deve ser publicada no Supabase usado pelo Portal (`utfxjadpntvbrhnkghbf`).
