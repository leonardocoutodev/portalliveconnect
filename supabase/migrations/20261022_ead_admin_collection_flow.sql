-- Live Connect EAD: online request -> Admin billing -> enrollment after payment
-- 2026-10-22

create table if not exists public.portal_ead_module_course_map (
  ouro_course_id text primary key,
  course_id uuid not null unique references public.courses(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.portal_ead_module_course_map enable row level security;
revoke all on public.portal_ead_module_course_map from anon, authenticated;
grant all on public.portal_ead_module_course_map to service_role;

create table if not exists public.portal_ead_formation_course_map (
  formation_slug text primary key references public.portal_formation_catalog(formation_slug) on delete cascade,
  course_id uuid not null references public.courses(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.portal_ead_formation_course_map enable row level security;
revoke all on public.portal_ead_formation_course_map from anon, authenticated;
grant all on public.portal_ead_formation_course_map to service_role;

insert into public.portal_ead_formation_course_map(formation_slug,course_id,updated_at)
select f.formation_slug,c.id,now()
from public.portal_formation_catalog f
join lateral (
  select c.id from public.courses c
  where c.type='pago' and c.active=true
    and private.portal_name_key(c.name)=private.portal_name_key(f.formation_name)
  order by c.created_at limit 1
) c on true
on conflict (formation_slug) do update set course_id=excluded.course_id,updated_at=now();

do $$
declare r record; v_course_id uuid;
begin
  for r in
    select distinct m.ouro_course_id,
      coalesce(o.name,m.mapped_ouro_name,m.portal_module_name) module_name,
      o.description
    from public.portal_formation_module_ouro_map m
    join public.ouro_course_catalog_cache o on o.ouro_course_id=m.ouro_course_id
    where m.ouro_course_id is not null and o.workload_hours>0
    order by m.ouro_course_id
  loop
    select course_id into v_course_id
    from public.portal_ead_module_course_map
    where ouro_course_id=r.ouro_course_id;
    if v_course_id is null then
      insert into public.courses(name,description,type,modules,free_certificate,active,featured,sort_order)
      values(
        'EAD • '||r.module_name,
        coalesce(nullif(r.description,''),'Módulo EAD Live Connect')||
          E'\n\nProduto interno do catálogo EAD. Não exibir no catálogo presencial.',
        'pago'::public.course_type,'[]'::jsonb,true,false,false,9999
      )
      returning id into v_course_id;
      insert into public.portal_ead_module_course_map(ouro_course_id,course_id)
      values(r.ouro_course_id,v_course_id);
    end if;
  end loop;
end $$;

alter table public.portal_enrollment_queue
  add column if not exists enrollment_id uuid references public.enrollments(id) on delete set null;

alter table public.payments drop constraint if exists payments_kind_check;
alter table public.payments add constraint payments_kind_check
check (kind = any (array[
  'matricula'::text,'primeira_mensalidade'::text,
  'profissao_rapida_total'::text,'ead_total'::text
]));

create or replace function private.ouro_portal_target_courses(p_queue_id uuid)
returns text[]
language plpgsql
security definer
set search_path to 'pg_catalog','private','public'
as $function$
declare
  v_course_name text;
  v_meta jsonb;
  v_ids text[];
begin
  select coalesce(c.name,li.metadata->>'course_name'),coalesce(li.metadata,'{}'::jsonb)
    into v_course_name,v_meta
  from public.portal_enrollment_queue q
  join public.lead_interests li on li.id=q.interest_id
  left join public.courses c on c.id=q.course_id
  where q.id=p_queue_id;

  if jsonb_typeof(v_meta->'ouro_course_ids')='array' then
    select coalesce(array_agg(x.course_id order by x.ord),'{}'::text[])
      into v_ids
    from (
      select value course_id,min(ord) ord
      from jsonb_array_elements_text(v_meta->'ouro_course_ids') with ordinality t(value,ord)
      where value ~ '^[0-9]+$'
      group by value
    ) x;
    if coalesce(cardinality(v_ids),0)>0 then return v_ids; end if;
  end if;

  if coalesce(v_meta->>'ouro_course_id','') ~ '^[0-9]+$' then
    return array[v_meta->>'ouro_course_id'];
  end if;

  if coalesce(v_course_name,'')='' then return '{}'::text[]; end if;

  select coalesce(array_agg(s.ouro_course_id order by s.first_order),'{}'::text[])
    into v_ids
  from (
    select m.ouro_course_id,min(m.module_order) first_order
    from public.portal_formation_catalog f
    join public.portal_formation_module_ouro_map m on m.formation_slug=f.formation_slug
    where private.portal_name_key(f.formation_name)=private.portal_name_key(v_course_name)
      and coalesce(m.ouro_course_id,'') ~ '^[0-9]+$'
    group by m.ouro_course_id
  ) s;
  return coalesce(v_ids,'{}'::text[]);
end;
$function$;

create or replace function public.sync_ead_total_payment()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public','private'
as $function$
declare
  v_lead uuid; v_course uuid; v_mode text; v_queue_id uuid; v_email text; v_result jsonb;
begin
  if new.kind<>'ead_total' then return new; end if;
  select e.lead_id,e.course_id,e.commercial_mode into v_lead,v_course,v_mode
  from public.enrollments e where e.id=new.enrollment_id;
  if v_lead is null or v_mode<>'ead_total' then return new; end if;

  select q.id into v_queue_id
  from public.portal_enrollment_queue q
  where q.enrollment_id=new.enrollment_id
     or (q.enrollment_id is null and q.lead_id=v_lead and q.course_id=v_course)
  order by case when q.enrollment_id=new.enrollment_id then 0 else 1 end,q.created_at desc
  limit 1 for update;
  if v_queue_id is null then return new; end if;

  if new.status::text='pendente' then
    update public.portal_enrollment_queue
       set enrollment_id=new.enrollment_id,
           status=case when status in ('nova','em_analise') then 'aguardando_pagamento' else status end,
           updated_at=now()
     where id=v_queue_id
       and status not in ('paga_aguardando_matricula','em_cadastro_ouro','matriculada_ouro','matriculada_manual','cancelada');
    return new;
  end if;

  if new.status::text='pago' or lower(coalesce(new.provider_status,'')) in ('approved','paid') then
    select lower(trim(coalesce(l.email,''))) into v_email from public.leads l where l.id=v_lead;
    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
      update public.portal_enrollment_queue
         set enrollment_id=new.enrollment_id,status='pendencia_documental',
             payment_approved_at=coalesce(payment_approved_at,now()),
             ouro_last_error='email_required_for_ouro_auto',updated_at=now()
       where id=v_queue_id;
      return new;
    end if;

    update public.portal_enrollment_queue
       set enrollment_id=new.enrollment_id,status='paga_aguardando_matricula',
           payment_approved_at=coalesce(payment_approved_at,now()),
           ouro_last_error=null,updated_at=now()
     where id=v_queue_id and status not in ('matriculada_ouro','matriculada_manual','cancelada');

    begin
      v_result:=private.portal_auto_process_paid_enrollment(v_queue_id);
      if coalesce((v_result->>'ok')::boolean,false) then
        update public.leads
           set status='matricula_confirmada',lead_score=100,archived=false,updated_at=now()
         where id=v_lead;
      end if;
    exception when others then
      update public.portal_enrollment_queue
         set ouro_last_error=left(sqlerrm,500),updated_at=now()
       where id=v_queue_id;
    end;
  end if;
  return new;
end;
$function$;

revoke all on function public.sync_ead_total_payment() from public,anon,authenticated;
grant execute on function public.sync_ead_total_payment() to service_role;

drop trigger if exists trg_sync_ead_total_payment on public.payments;
create trigger trg_sync_ead_total_payment
after insert or update of status,provider_status on public.payments
for each row when (new.kind='ead_total')
execute function public.sync_ead_total_payment();

-- portal_ead_request_create(jsonb) and private.is_valid_cpf(text)
-- are deployed in production as part of this release and are intentionally
-- callable only by service_role. See release documentation for the full flow.
