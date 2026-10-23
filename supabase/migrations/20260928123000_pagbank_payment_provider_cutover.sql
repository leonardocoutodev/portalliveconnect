-- Live Connect: cutover de Mercado Pago para PagBank/PagSeguro
-- Aplicar somente após configurar PAGBANK_TOKEN e concluir homologação do checkout.

alter table public.payment_checkout_sessions
  add column if not exists provider_checkout_id text,
  add column if not exists checkout_url text;

alter table public.payment_checkout_sessions
  alter column provider set default 'pagbank'::text;

create index if not exists payment_checkout_sessions_provider_checkout_idx
  on public.payment_checkout_sessions(provider, provider_checkout_id)
  where provider_checkout_id is not null;

comment on column public.payment_checkout_sessions.provider_checkout_id is
  'Identificador neutro do checkout no provedor de pagamento atual (ex.: PagBank CHEC_...).';
comment on column public.payment_checkout_sessions.checkout_url is
  'URL neutra de redirecionamento para o checkout hospedado do provedor.';

create or replace function public.admin_payment_checkout_sessions_v2(p_limit integer default 50)
returns table(
  id uuid,
  created_at timestamptz,
  student_name text,
  course_name text,
  scope text,
  amount numeric,
  status text,
  provider text,
  provider_checkout_id text,
  provider_payment_id text,
  checkout_url text,
  paid_at timestamptz
)
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
begin
  if not (public.is_master_admin() or public.is_admin_comercial()) then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return query
  select
    s.id,s.created_at,l.full_name,c.name,s.scope,s.amount,s.status,
    coalesce(nullif(s.provider,''),'legacy') as provider,
    s.provider_checkout_id,s.provider_payment_id,
    coalesce(s.checkout_url,s.init_point) as checkout_url,s.paid_at
  from public.payment_checkout_sessions s
  join public.leads l on l.id=s.lead_id
  join public.enrollments e on e.id=s.enrollment_id
  join public.courses c on c.id=e.course_id
  where public.can_view_lead(s.lead_id)
  order by s.created_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
end;
$function$;

revoke all on function public.admin_payment_checkout_sessions_v2(integer) from public,anon;
grant execute on function public.admin_payment_checkout_sessions_v2(integer) to authenticated;

drop function if exists public.portal_mp_bridge_create(uuid);
drop function if exists public.portal_mp_bridge_payment(text);
