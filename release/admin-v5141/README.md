# Admin Live Connect V5.14.1 — hotfix de inicialização

Base: V5.14.0.

## Incidente

Após publicar a V5.14.0, o navegador exibia **Falha ao iniciar o Admin**.

A causa raiz foi reproduzida no próprio pacote com validação explícita em modo ES Module:

`SyntaxError: Unexpected identifier 'check'`

Arquivo:

`assets/js/v360/admin-central.js`

O estado vazio da Central de Notificações havia sido escrito como string delimitada por aspas simples contendo a expressão `${icon('check')}`. A aspa de `'check'` encerrava a string antes da hora. Como `admin-central.js` é um import estático de `admin-entry.js`, o navegador falhava durante a ligação da árvore de módulos antes de executar a primeira linha do entrypoint. Por isso `window.__lcAdminBundleLoaded` nunca era marcado e o fallback aparecia após 8 segundos.

## Correção V5.14.1

- template do estado vazio convertido para template literal válido;
- cache-bust atualizado de `5140` para `5141`;
- imports runtime atualizados para `5141`;
- fallback do index atualizado para mencionar V5.14.1;
- backend/migration V5.14 permanece inalterado.

## Validação específica

- todos os JS: `node --experimental-default-type=module --check`;
- verificação de imports relativos sem arquivos faltantes;
- carregamento completo de `admin-entry.js` e de sua árvore de imports;
- confirmação de `window.__lcAdminBundleLoaded === true` no smoke test;
- index, admin-entry, admin-central, modal, CSS e build.json servidos localmente com HTTP 200;
- ZIP completo validado com `unzip -t`.

Pacote: `Live_Connect_ADMIN_FULL_V5.14.1_HOTFIX_BOOT_CLOUDFLARE.zip`.

SHA-256: `33766e19ab77ec1e96f9407679678fdd0d117466e3b5dc5475fd870489b105d6`.
