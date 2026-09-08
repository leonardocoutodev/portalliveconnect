# Live Connect — Chatbot comercial independente

## Regra de arquitetura
O chatbot da Live Connect é independente do LCAI e dos demais projetos pessoais da LC Soluções Digitais.

Ele não usa:
- memória do LCAI;
- motor de aprendizado do LCAI;
- agentes compartilhados;
- base de conhecimento de outros produtos;
- automações comerciais externas à Live Connect.

## Escopo do Lico
Fluxo simples:
1. entender o que o visitante procura;
2. identificar curso/área;
3. entender modalidade/período;
4. apresentar curso e condição vigente;
5. perguntar se deseja avançar;
6. coletar primeiro nome;
7. coletar WhatsApp;
8. registrar lead e permitir continuidade/handoff da equipe.

## Regras conversacionais
- saudações nunca são interpretadas como nome;
- “me chamo Leonardo” salva “Leonardo”;
- primeiro nome é suficiente para atendimento;
- nome completo fica para matrícula, quando necessário;
- preço/endereço/atendente podem ser perguntados a qualquer momento;
- não há questionário longo;
- não há aprendizado autônomo no chatbot.

Backend: `supabase/functions/portal-commercial-chat/index.ts`
Versão: `liveconnect-basic-sales-1.0`.
