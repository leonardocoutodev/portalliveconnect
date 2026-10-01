# Academic360 Push Notifications — 2026-10-01

## Produção

Projeto Supabase acadêmico: `cwwlxcnbtzorbjxelenp`

Edge Function: `ga-push-dispatch`
- status: ACTIVE
- `verify_jwt=true`
- Web Push baseado em VAPID
- biblioteca edge-native: `@mmmike/web-push@1.3.0`

## Funcionalidades

- aluno registra o próprio celular/navegador;
- push funciona com o portal fechado;
- comunicado pode atingir aluno específico, turma ou todos os alunos;
- lançamento de notas dispara aviso aos alunos afetados;
- frequência atualizada dispara aviso;
- publicação/atualização de material dispara aviso;
- clique no push abre diretamente notas, frequência, materiais ou mensagens;
- o aluno pode enviar um teste e desativar o próprio aparelho;
- iPhone/iPad recebe orientação para adicionar o portal à Tela de Início antes da ativação.

## Banco

- `ga_push_subscriptions`: dispositivos e estado de entrega;
- `ga_push_history`: auditoria de entregas/falhas;
- `ga_push_config`: VAPID server-side.

A chave privada VAPID de produção não é versionada no GitHub.

## Artefatos

- `Gestao_Academica_360_V360.10_PUSH_NOTIFICATIONS.zip`
  - SHA-256: `88df6a7e38a60785e0f51257d14d57bf8decf7c5c4ee308f39bbabedd2da1f28`
- `Live_Connect_ADMIN_FULL_V5.15.2_ACADEMIC360_PUSH_CLOUDFLARE.zip`
  - SHA-256: `9ed519afc8834136abe040d6c6f8fd50b8db914c53a56616a774c1b595e42095`

## Publicação frontend

O backend Supabase já está publicado. Publique o pacote frontend correspondente ao ambiente usado pelos alunos. O pacote Admin V5.15.2 contém a mesma versão em `/academic360/`.
