# Admin Live Connect V5.15.0 — Gestão Acadêmica 360

Base: V5.14.2 Runtime Init Hotfix.

## Integração

- novo grupo `ACADÊMICO`;
- nova área `Gestão Acadêmica 360`;
- portal acadêmico incluído no próprio pacote em `/academic360/`;
- leitura e gravação no Supabase acadêmico `cwwlxcnbtzorbjxelenp`;
- Supabase operacional `utfxjadpntvbrhnkghbf` preservado e isolado;
- bridge same-origin entre Admin e iframe para estado, navegação e refresh;
- sem `service_role` ou segredo Supabase no navegador;
- hotfix V5.14.2 preservado.

## Validações

- sintaxe de todos os módulos JavaScript validada com Node;
- rotas principais e assets retornaram HTTP 200 em servidor local;
- portal acadêmico contém operações `insert`, `update`, `upsert` e `delete`;
- varredura sem marcadores de `service_role`/secret key;
- ZIP validado com `unzip -t`.

## Pacote

`Live_Connect_ADMIN_FULL_V5.15.0_ACADEMIC360_INTEGRATION_CLOUDFLARE.zip`

SHA-256:

`ab15d8aca4bfb178fc09408b5abf08a3eb944019ed28c80c7970ddaff7c14bb7`

Publicar o pacote completo de Static Assets. Não misturar arquivos com V5.14.2.