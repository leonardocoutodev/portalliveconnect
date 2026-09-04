-- Live Connect Admin V5.11.1 — auditoria financeira exclusiva do proprietário

create or replace function public.school_finance_audit(p_limit integer default 200)
returns table(
  id uuid,
  payment_id uuid,
  actor_name text,
  action text,
  note text,
  created_at timestamptz,
  before_data jsonb,
  after_data jsonb
)
language plpgsql
stable
security definer
set search_path='pg_catalog','public','private'
as $$
begin
  if not public.is_owner() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  return query
  select
    a.id,
    a.payment_id,
    coalesce(p.full_name,'Sistema'),
    a.action,
    a.note,
    a.created_at,
    a.before_data,
    a.after_data
  from public.financial_audit_logs a
  left join public.profiles p on p.id=a.actor_user_id
  order by a.created_at desc
  limit greatest(1,least(coalesce(p_limit,200),500));
end $$;

revoke all on function public.school_finance_audit(integer) from public,anon;
grant execute on function public.school_finance_audit(integer) to authenticated;
