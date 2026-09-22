# Admin Live Connect V5.14.2 — runtime init hotfix

Base: V5.14.1.

## Incidente

Após publicar a V5.14.1, o navegador conseguiu carregar o módulo principal, mas a montagem da Visão geral falhou com:

`ReferenceError: Cannot access 'notificationIconFor' before initialization`

## Causa raiz

Em `mountAdminCentral()`, o primeiro:

`await renderView(firstView)`

era executado antes da inicialização lexical de:

`const notificationIconFor = ...`

A view `central` renderiza as notificações imediatamente e chamava `notificationIconFor()` enquanto esse `const` ainda estava na Temporal Dead Zone (TDZ).

## Correção

- `notificationIconFor` convertido para function declaration hoisted;
- o primeiro `renderView(firstView)` foi movido para depois da inicialização da busca global e da Central de Notificações;
- cache-bust atualizado para `5142`;
- backend V5.14 permanece inalterado.

## Validação específica

Foi executado um teste de runtime com DOM e RPCs simulados contra as duas versões:

- V5.14.1: falha reproduzida com o mesmo `ReferenceError`;
- V5.14.2: `mountAdminCentral()` conclui, seleciona `central` e renderiza `Centro operacional`.

Além disso:

- todos os JS passaram em `node --experimental-default-type=module --check`;
- referências/imports relativos sem arquivos faltantes;
- index, admin-entry, admin-central, floating chat, CSS e build.json responderam HTTP 200 localmente;
- ZIP íntegro em `unzip -t`.

Pacote:

`Live_Connect_ADMIN_FULL_V5.14.2_RUNTIME_INIT_HOTFIX_CLOUDFLARE.zip`

SHA-256:

`cf655994b433ecba7155357524ffe52111c5053bf1d3f7a6d05297743636516e`

Publicar o pacote completo de Static Assets; não misturar arquivos com V5.14.0/V5.14.1.
