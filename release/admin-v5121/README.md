# Admin Live Connect V5.12.1 — emojis no chat interno

Base: V5.12.0 com matrículas gratuitas e pagas separadas.

## Chat interno

Foi adicionado um seletor de emojis ao mensageiro interno:

- botão 😊 ao lado de anexo e menções;
- categorias: Recentes, Sorrisos, Gestos, Corações, Trabalho e Destaques;
- emojis recentes persistidos localmente no navegador;
- inserção exatamente na posição atual do cursor;
- Esc fecha o seletor;
- clique fora fecha o seletor;
- abrir menções fecha emojis e vice-versa;
- seletor fecha após envio;
- Enter continua enviando;
- Shift+Enter continua quebrando linha;
- layout responsivo em mobile;
- modo somente leitura não permite abrir o seletor.

Cache-bust: `5121`.

## Deploy

Publicar o pacote completo V5.12.1 no mesmo Worker/Static Assets do Admin. Não misturar arquivos isolados com versões anteriores.
