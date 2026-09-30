# Gestão Acadêmica 360 ↔ Admin Live Connect

## Arquitetura

A integração mantém dois projetos Supabase independentes:

- Admin Live Connect: `utfxjadpntvbrhnkghbf`
- Gestão Acadêmica 360: `cwwlxcnbtzorbjxelenp`

O portal acadêmico autentica, lê e grava no Supabase acadêmico usando a chave publishable e a sessão autenticada do próprio usuário. Nenhuma `service_role` deve ser exposta no navegador.

## Modo embutido

O portal foi preparado para abrir com `?embed=1` e ser montado dentro do Admin Live Connect por iframe.

Eventos publicados pelo portal via `postMessage`:

- `academic360:auth`
- `academic360:context`
- `academic360:ready`
- `academic360:state`
- `academic360:error`

Comandos aceitos do Admin:

- `academic360:navigate`
- `academic360:refresh`
- `academic360:state`

## Dados externos

Tabelas principais consumidas no projeto acadêmico:

`ga_profiles`, `ga_institutions`, `ga_students`, `ga_teachers`, `ga_courses`, `ga_classes`, `ga_subjects`, `ga_assessments`, `ga_grades`, `ga_attendance`, `ga_materials`, `ga_messages`, `ga_message_reads`, `ga_staff_chat_messages`, `ga_staff_chat_reads`, `ga_admin_alerts`, `ga_invitations`.

RPCs:

`ga_bootstrap_institution`, `ga_create_invitation`, `ga_redeem_invitation`, `ga_refresh_admin_alerts`, `ga_refresh_notifications`.

Edge Functions:

`student-access` e `staff-access`.

## Segurança

O portal embutido só deve aceitar frame de superfícies Live Connect. Não reutilizar a conexão Supabase do Admin para o projeto acadêmico e não colocar chave secreta no frontend.

## Situação do frontend V5.14

O repositório documenta o Admin V5.14.x, mas os Static Assets de produção (`admin-entry.js`, `admin-central.js`, CSS e `build.json`) não estão versionados no `main`. A inclusão definitiva do item de menu/iframe no Admin depende de recuperar o pacote V5.14.2 real.