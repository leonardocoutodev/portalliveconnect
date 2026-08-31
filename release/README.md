# Pacotes de produção

## Admin Live Connect

Destino oficial:

`https://admin.liveconnectios.workers.dev/`

Versão de referência do Admin:

**V4.4 — Revisão estrutural de Produto, UI e UX**

Principais mudanças:
- correção do deslocamento duplo da sidebar que espremia o conteúdo;
- layout desktop passa a usar toda a largura restante da viewport;
- cards, métricas, filtros e painéis com densidade revisada;
- tabelas de uso comum deixam de forçar rolagem horizontal em desktop;
- datasets realmente largos continuam protegidos por scroll interno;
- no mobile, tabelas viram cards com rótulos;
- sidebar vira drawer;
- modais e Editor 360° responsivos;
- cache-busting V4.4 nos assets principais.

O Admin é tratado como aplicação independente do Portal.

## Portal público

O Portal permanece separado do Admin. Alterações de UI do Admin não exigem novo deploy do Portal público.
