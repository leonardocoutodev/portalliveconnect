# Admin Live Connect V5.11.4 — recuperação

## Diagnóstico
O Admin usa deploy completo de Static Assets no Cloudflare. Um ZIP parcial não é equivalente a um patch incremental: ao substituir o conjunto publicado por poucos arquivos, os demais assets podem desaparecer e o Admin deixa de iniciar.

O hotfix V5.11.3 continha somente 5 arquivos. O pacote completo continha o restante do Admin.

## Hardening V5.11.4
- o módulo do chat interno deixou de ser dependência estática do bootstrap principal;
- o Admin carrega primeiro;
- o mensageiro é importado dinamicamente com isolamento de erro;
- um problema futuro no chat não derruba mais a Central inteira;
- Enter envia; Shift + Enter quebra linha;
- cache-bust 5114.

## Deploy
Publicar o pacote COMPLETO V5.11.4 no mesmo Worker/Static Assets do Admin.
Não usar o ZIP hotfix como substituição integral do deploy.
