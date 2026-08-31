create table if not exists public.young_apprentice_registration_forms (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references public.leads(id) on delete cascade,
  interest_id uuid not null references public.lead_interests(id) on delete cascade,
  data_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'preenchida'
    check (status in ('preenchida','em_contato','confirmada','cancelada')),
  generated_at timestamptz not null default now(),
  printed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (interest_id)
);

create index if not exists young_apprentice_forms_lead_idx
  on public.young_apprentice_registration_forms(lead_id, generated_at desc);

create index if not exists young_apprentice_forms_status_idx
  on public.young_apprentice_registration_forms(status, generated_at desc);

alter table public.young_apprentice_registration_forms enable row level security;
revoke all on public.young_apprentice_registration_forms from anon, authenticated;
grant all on public.young_apprentice_registration_forms to service_role;

create or replace function public.school_commercial_young_apprentice_registrations(p_limit integer default 200)
returns table(
  form_id uuid,
  lead_id uuid,
  interest_id uuid,
  full_name text,
  whatsapp text,
  age integer,
  birth_date date,
  currently_studying boolean,
  school_status text,
  available_shift text,
  status text,
  generated_at timestamptz,
  printed_at timestamptz
)
language plpgsql
stable
security definer
set search_path='pg_catalog','public'
as $$
begin
  if not public.is_admin_comercial() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  return query
  select
    f.id,f.lead_id,f.interest_id,l.full_name,l.whatsapp,l.age,l.birth_date,l.currently_studying,
    f.data_snapshot->>'school_status',
    f.data_snapshot->>'available_shift',
    f.status,f.generated_at,f.printed_at
  from public.young_apprentice_registration_forms f
  join public.leads l on l.id=f.lead_id
  order by f.generated_at desc
  limit greatest(1,least(coalesce(p_limit,200),500));
end
$$;

create or replace function public.admin_get_young_apprentice_registration_form(p_form_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public'
as $$
declare v_out jsonb;
begin
  if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
  select to_jsonb(f) into v_out from public.young_apprentice_registration_forms f where f.id=p_form_id;
  return v_out;
end
$$;

create or replace function public.admin_mark_young_apprentice_registration_printed(p_form_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_out jsonb;
begin
  if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
  update public.young_apprentice_registration_forms
  set printed_at=coalesce(printed_at,now()),updated_at=now()
  where id=p_form_id
  returning to_jsonb(young_apprentice_registration_forms.*) into v_out;
  if v_out is null then raise exception 'form_not_found' using errcode='P0002'; end if;
  return v_out;
end
$$;

create or replace function public.school_commercial_set_young_apprentice_status(p_form_id uuid,p_status text)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_out jsonb;
begin
  if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_status not in ('preenchida','em_contato','confirmada','cancelada') then
    raise exception 'invalid_status' using errcode='22023';
  end if;
  update public.young_apprentice_registration_forms
  set status=p_status,updated_at=now()
  where id=p_form_id
  returning to_jsonb(young_apprentice_registration_forms.*) into v_out;
  if v_out is null then raise exception 'form_not_found' using errcode='P0002'; end if;
  return v_out;
end
$$;

revoke all on function public.school_commercial_young_apprentice_registrations(integer) from public,anon;
grant execute on function public.school_commercial_young_apprentice_registrations(integer) to authenticated;
revoke all on function public.admin_get_young_apprentice_registration_form(uuid) from public,anon;
grant execute on function public.admin_get_young_apprentice_registration_form(uuid) to authenticated;
revoke all on function public.admin_mark_young_apprentice_registration_printed(uuid) from public,anon;
grant execute on function public.admin_mark_young_apprentice_registration_printed(uuid) to authenticated;
revoke all on function public.school_commercial_set_young_apprentice_status(uuid,text) from public,anon;
grant execute on function public.school_commercial_set_young_apprentice_status(uuid,text) to authenticated;
