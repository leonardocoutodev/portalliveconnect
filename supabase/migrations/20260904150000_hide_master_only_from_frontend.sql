-- Ocultação real de registros master_only do frontend
-- 2026-09-04
-- Mantém dados, matrículas, financeiro, auditoria e acesso acadêmico ativos.
-- Registros master_only deixam de aparecer em listagens/resumos normais,
-- inclusive para o admin principal. Acesso técnico explícito por RPC master-only
-- continua possível quando a função específica não usa can_view_lead().

create or replace function public.can_view_lead(p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','public','private'
as $$
  select not exists (
    select 1
    from private.student_visibility sv
    where sv.lead_id = p_lead_id
      and sv.visibility_scope = 'master_only'
  );
$$;

revoke all on function public.can_view_lead(uuid) from public, anon;
grant execute on function public.can_view_lead(uuid) to authenticated, service_role;
