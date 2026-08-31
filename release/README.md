# Pacote de produção

O deploy do frontend usa um pacote ZIP na raiz desta pasta com o nome:

`portal.zip`

O `netlify.toml` descompacta esse arquivo para `dist/` durante o build.

## Versão de referência

**V4.0 — Ficha de inscrição do Projeto Jovem Aprendiz**

A V4.0 inclui:
- ficha pública completa no Projeto Jovem Aprendiz;
- integração da ficha ao CRM;
- situação escolar e turno disponível;
- responsável legal para participante menor de 18 anos;
- tela Comercial > Jovem Aprendiz;
- impressão da ficha e atualização de status;
- backend dedicado `portal-young-apprentice-submit`;
- rota `service=young` no portal gateway.

O pacote local de release deve ser publicado como `release/portal.zip` antes do deploy do frontend.
