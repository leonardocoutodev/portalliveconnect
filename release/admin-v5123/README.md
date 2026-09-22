# Admin Live Connect V5.12.3 — emojis expandidos

Base: V5.12.2.

## Chat interno

O seletor de emojis foi ampliado sem alterar o restante do chat.

Categorias:
- Recentes
- Reações
- Pessoas
- Mãos
- Corações
- Comemoração
- Trabalho
- Estudos
- Atendimento
- Dinheiro
- Tecnologia
- Alertas
- Símbolos

Entre as novas reações estão: 🤡, 🙄, 🤨, 🧐, 😏, 🫣, 🤪, 🥴, 😵‍💫, 🤬, 👻, 💀, 👽 e 🤖.

O histórico de emojis recentes foi preservado usando o mesmo namespace de armazenamento local da V5.12.2.

Cache-bust: `5123`.

O pacote completo inclui em `release-notes/admin-v5123-expanded-emojis.patch` o diff do seletor em relação à V5.12.2.

## Validação

- JavaScript validado com `node --check`;
- `build.json` válido;
- ZIP íntegro com `unzip -t`;
- `index.html`, JavaScript do chat e CSS servidos localmente com HTTP 200.

Fazer deploy do pacote completo de Static Assets, não parcial.
