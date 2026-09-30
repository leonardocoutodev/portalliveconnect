# Admin Live Connect V5.15.1 — Academic360 SSO

Base: V5.15.0 Academic360 Integration.

## Entrega

- SSO seguro entre o Admin Live Connect e o Portal Acadêmico;
- Monique Gomes do Admin (coadmin) vinculada por UUID ao perfil acadêmico Direção;
- ao abrir Gestão Acadêmica 360 dentro do Admin, a sessão acadêmica é criada automaticamente;
- usuários do Admin sem vínculo continuam usando o login acadêmico normal;
- Supabase operacional e acadêmico permanecem independentes;
- nenhuma service_role é exposta no navegador.

## Backend

- tabela protegida: `public.ga_sso_links`;
- Edge Function: `academic-admin-sso`;
- o JWT do Admin é validado contra o projeto `utfxjadpntvbrhnkghbf`;
- somente após a validação e o vínculo ativo é emitido um token acadêmico de uso único;
- destino atual da Monique: perfil `Direção` no projeto `cwwlxcnbtzorbjxelenp`.

## Pacote

`Live_Connect_ADMIN_FULL_V5.15.1_ACADEMIC360_SSO_CLOUDFLARE.zip`

SHA-256:

`0dc58f94b6aaf627653b3b8c960d9bd3ebfcc28ee0ea8c1b4a8539504f6f58fc`

Publicar o pacote completo. Não misturar arquivos com V5.15.0 ou V5.14.2.
