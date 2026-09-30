# Gestão Acadêmica 360 ↔ Admin Live Connect

## Arquitetura

A integração mantém dois projetos Supabase independentes:

- Admin Live Connect: `utfxjadpntvbrhnkghbf`
- Gestão Acadêmica 360: `cwwlxcnbtzorbjxelenp`

O portal acadêmico autentica, lê e grava no Supabase acadêmico usando a chave publishable e a sessão autenticada do próprio usuário. Nenhuma `service_role` é exposta no navegador.

## Integração concluída — Admin V5.15.0

Base: Admin V5.14.2 Runtime Init Hotfix.

O pacote V5.15.0 adiciona:

- grupo `ACADÊMICO` no menu do Admin;
- item `Gestão Acadêmica 360`;
- portal acadêmico embarcado em `/academic360/index.html?embed=1`;
- botão de atualização do ambiente acadêmico;
- opção para abrir o portal em tela cheia;
- indicador de estado da sessão/contexto acadêmico;
- isolamento completo entre o Supabase operacional e o acadêmico.

O hotfix de inicialização da V5.14.2 foi preservado.

## Modo embutido

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

A ponte foi endurecida para comunicação same-origin no pacote integrado.

## Dados externos

Tabelas principais consumidas no projeto acadêmico:

`ga_profiles`, `ga_institutions`, `ga_students`, `ga_teachers`, `ga_courses`, `ga_classes`, `ga_subjects`, `ga_assessments`, `ga_grades`, `ga_attendance`, `ga_materials`, `ga_messages`, `ga_message_reads`, `ga_staff_chat_messages`, `ga_staff_chat_reads`, `ga_admin_alerts`, `ga_invitations`.

Operações verificadas no frontend acadêmico incluem leitura e gravação por `insert`, `update`, `upsert` e `delete`, sempre no projeto acadêmico.

RPCs:

`ga_bootstrap_institution`, `ga_create_invitation`, `ga_redeem_invitation`, `ga_refresh_admin_alerts`, `ga_refresh_notifications`.

Edge Functions:

`student-access` e `staff-access`.

## Segurança

- não reutilizar a conexão Supabase do Admin para o projeto acadêmico;
- não expor `service_role` ou chave secreta no frontend;
- manter RLS e autenticação do projeto acadêmico como autoridade de acesso aos dados acadêmicos;
- a comunicação Admin ↔ iframe é restrita ao mesmo origin no pacote V5.15.0.

## Pacote

`Live_Connect_ADMIN_FULL_V5.15.0_ACADEMIC360_INTEGRATION_CLOUDFLARE.zip`

SHA-256:

`ab15d8aca4bfb178fc09408b5abf08a3eb944019ed28c80c7970ddaff7c14bb7`

Publicar o pacote completo como Static Assets. Não misturar arquivos com V5.14.2.