# Fix — edição de matrícula no Admin

Data: 2026-10-02

## Sintoma
A tela `Editar matrícula` abria normalmente, mas `Salvar alterações` retornava HTTP 403.

## Causa
`admin_student_update_enrollment(uuid,jsonb)` rodava como SECURITY INVOKER e chamava internamente `ensure_free_registration_form_internal(uuid)`, cuja execução é intencionalmente restrita. O PostgreSQL retornava SQLSTATE 42501.

## Correção
- `admin_student_update_enrollment` passou a SECURITY DEFINER;
- `PUBLIC` e `anon` não podem executar a função;
- somente `authenticated` e `service_role` têm EXECUTE;
- a função mantém a autorização interna `school_has_permission('edit_students')`;
- `search_path` já estava fixado em `pg_catalog, public`.

## Verificação
Foi simulada a sessão do usuário master_admin e executada uma atualização vazia da matrícula de Hítalo Viana Maia dentro de uma transação revertida. A função retornou a matrícula corretamente, sem persistir alterações.
