# Portal Live Connect — KingHost Windows / IIS

Domínio oficial:

`https://www.liveconnect.com.br`

## Diagnóstico do 403.14

A hospedagem está em IIS/Windows e o caminho físico informado pelo servidor é:

`d:\web\localuser\liveconnect\www`

O erro 403.14 acontece quando o IIS chega ao diretório, mas não encontra/usa um documento padrão.

## Correção

O pacote KingHost Windows contém `web.config` na raiz com:

- `index.html` como documento padrão;
- redirect permanente HTTP -> HTTPS;
- redirect permanente sem-www -> www;
- preservação de query string;
- redirect de `/admin` para `https://admin.liveconnectios.workers.dev/`;
- página 404 personalizada;
- MIME para WebP e webmanifest;
- cache estático e compressão.

## Migração de domínio

Todos os URLs públicos do pacote foram migrados de:

`https://portallc.netlify.app`

para:

`https://www.liveconnect.com.br`

Incluindo:

- canonical;
- hreflang;
- Open Graph;
- Twitter image/url;
- JSON-LD;
- Course schema;
- breadcrumbs;
- sitemap;
- robots.txt;
- `CONFIG.brand.canonicalOrigin`.

## Supabase

As Edge Functions públicas também foram atualizadas para usar `https://www.liveconnect.com.br` como origem principal/fallback CORS.

Versões após a migração:

- portal-gateway v4
- portal-enrollment-submit v11
- portal-lead-submit v5
- portal-analytics-event v4
- portal-payment v6
- portal-enrollment-preferences v2
- ouro-student-portal v6
- portal-young-apprentice-submit v2

Os domínios antigos permanecem apenas como origens permitidas de transição/rollback, não como origem principal.

## Deploy

Enviar o conteúdo do ZIP diretamente para a pasta `www`:

- `www/index.html`
- `www/web.config`
- `www/assets/...`
- `www/cursos/...`

Não colocar o site dentro de uma subpasta.

Se existir um `index.htm` padrão antigo da hospedagem, removê-lo.

O SSL deve estar ativo para `www.liveconnect.com.br` antes de forçar HTTPS.
