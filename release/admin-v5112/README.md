# Live Connect Admin V5.11.2 — Correção crítica de bootstrap

## Causa
O pacote V5.11.1 continha todos os assets esperados, porém o módulo `floating-school-chat.js` tinha um bloco condicional malformado dentro de `openDrawer()` (busca / fixados / vínculos / tarefas).

Como `admin-entry.js` importa esse módulo estaticamente, o navegador interrompia o carregamento do módulo inteiro antes do boot. A tela de fallback interpretava isso genericamente como ausência de assets, embora o ZIP estivesse completo.

## Correção
- reescrita do `openDrawer()` com blocos independentes e sintaxe validada;
- cache-bust atualizado para `v=5112`;
- service worker atualizado para `v=5112`;
- mensagem de fallback corrigida para distinguir falha de inicialização de falta de arquivos;
- validação estrita de sintaxe aplicada aos 10 módulos JavaScript;
- ZIP validado com teste de integridade.

## Deploy
Publicar o pacote completo V5.11.2 manualmente no mesmo Worker do Admin no Cloudflare.
