# Admin V5.11.6 — Chat em formato de mensageiro

- Geral separado como conversa de toda a equipe.
- Privados 1:1 aparecem pelo nome da outra pessoa, não pelo slug técnico.
- Sidebar com avatar, departamento, última mensagem, horário e não lidas.
- Proprietário tem seção recolhida **Acompanhar** para privados fora do Comercial.
- Acompanhamento é somente leitura, sem presença/recibo visível aos participantes.
- Conversas supervisionadas não entram no badge, autoabertura nem push do proprietário.
- Mobile usa lista de conversas + thread em tela cheia.
- Backend: `school_chat_people()` + canais privados por pares.
