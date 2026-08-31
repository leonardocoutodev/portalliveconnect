create or replace function public.school_admin_global_search(
  p_query text,
  p_limit integer default 20
)
returns table(
  result_type text,
  view_name text,
  ref_id uuid,
  label text,
  subtitle text,
  rank_order integer
)
language sql
stable
security invoker
set search_path='pg_catalog','public'
as $$
  with params as (
    select
      nullif(trim(coalesce(p_query,'')),'') as q,
      nullif(regexp_replace(trim(coalesce(p_query,'')),'\D','','g'),'') as digits_q
  ),
  results as (
    select
      'Lead'::text as result_type,'com-leads'::text as view_name,l.id as ref_id,l.full_name as label,
      concat_ws(' • ',nullif(l.whatsapp,''),nullif(l.email,''),replace(l.status::text,'_',' ')) as subtitle,
      10 as rank_order,l.updated_at as sort_at
    from public.leads l, params p
    where public.is_master_admin()
      and l.deleted_at is null
      and p.q is not null
      and (
        l.full_name ilike '%'||p.q||'%'
        or (p.digits_q is not null and length(p.digits_q)>=3 and coalesce(l.whatsapp,'') ilike '%'||p.digits_q||'%')
        or coalesce(l.email,'') ilike '%'||p.q||'%'
        or coalesce(l.source,'') ilike '%'||p.q||'%'
      )
    union all
    select
      'Aluno'::text,'sec-students'::text,l.id,l.full_name,
      concat_ws(' • ',c.name,cl.secretary_label,e.schedule_text),20,e.enrolled_at
    from public.enrollments e
    join public.leads l on l.id=e.lead_id
    join public.courses c on c.id=e.course_id
    left join public.classes cl on cl.id=e.class_id
    cross join params p
    where public.is_master_admin()
      and e.cancelled_at is null
      and p.q is not null
      and (
        l.full_name ilike '%'||p.q||'%'
        or (p.digits_q is not null and length(p.digits_q)>=3 and coalesce(l.whatsapp,'') ilike '%'||p.digits_q||'%')
        or c.name ilike '%'||p.q||'%'
      )
    union all
    select
      'Contrato'::text,'sec-contracts'::text,ct.id,l.full_name,
      concat_ws(' • ',ct.contract_number,c.name,ct.status::text),30,ct.generated_at
    from public.contracts ct
    join public.leads l on l.id=ct.lead_id
    left join public.enrollments e on e.id=ct.enrollment_id
    left join public.courses c on c.id=e.course_id
    cross join params p
    where public.is_master_admin()
      and p.q is not null
      and (
        l.full_name ilike '%'||p.q||'%'
        or coalesce(ct.contract_number,'') ilike '%'||p.q||'%'
        or coalesce(c.name,'') ilike '%'||p.q||'%'
      )
    union all
    select
      'Jovem Aprendiz'::text,'com-young'::text,f.lead_id,l.full_name,
      concat_ws(' • ',l.whatsapp,f.data_snapshot->>'available_shift',f.status),15,f.generated_at
    from public.young_apprentice_registration_forms f
    join public.leads l on l.id=f.lead_id
    cross join params p
    where public.is_master_admin()
      and p.q is not null
      and (
        l.full_name ilike '%'||p.q||'%'
        or (p.digits_q is not null and length(p.digits_q)>=3 and coalesce(l.whatsapp,'') ilike '%'||p.digits_q||'%')
      )
  )
  select r.result_type,r.view_name,r.ref_id,r.label,r.subtitle,r.rank_order
  from results r
  order by r.rank_order,r.sort_at desc nulls last
  limit greatest(1,least(coalesce(p_limit,20),50))
$$;

revoke all on function public.school_admin_global_search(text,integer) from public,anon;
grant execute on function public.school_admin_global_search(text,integer) to authenticated;

create or replace function public.school_commercial_leads_search(
  p_query text default null,
  p_status text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table(
  total_count bigint,
  lead_id uuid,
  full_name text,
  whatsapp text,
  email text,
  status text,
  source text,
  lead_score integer,
  created_at timestamptz,
  next_followup timestamptz,
  followup_note text
)
language sql
stable
security invoker
set search_path='pg_catalog','public'
as $$
  with params as (
    select
      nullif(trim(coalesce(p_query,'')),'') as q,
      nullif(regexp_replace(trim(coalesce(p_query,'')),'\D','','g'),'') as digits_q
  ),
  filtered as (
    select
      l.id,l.full_name,l.whatsapp,l.email,l.status::text as status,l.source,l.lead_score,l.created_at
    from public.leads l
    cross join params p
    where public.is_admin_comercial()
      and l.deleted_at is null
      and (
        p.q is null
        or l.full_name ilike '%'||p.q||'%'
        or (p.digits_q is not null and length(p.digits_q)>=3 and coalesce(l.whatsapp,'') ilike '%'||p.digits_q||'%')
        or coalesce(l.email,'') ilike '%'||p.q||'%'
        or coalesce(l.source,'') ilike '%'||p.q||'%'
      )
      and (
        nullif(trim(coalesce(p_status,'')),'') is null
        or l.status::text=trim(p_status)
      )
  )
  select
    count(*) over() as total_count,
    f.id,f.full_name,f.whatsapp,f.email,f.status,f.source,f.lead_score,f.created_at,
    fu.scheduled_at,fu.note
  from filtered f
  left join lateral (
    select scheduled_at,note
    from public.followups x
    where x.lead_id=f.id and x.status='pendente'
    order by x.scheduled_at
    limit 1
  ) fu on true
  order by f.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),200))
  offset greatest(0,coalesce(p_offset,0))
$$;

revoke all on function public.school_commercial_leads_search(text,text,integer,integer) from public,anon;
grant execute on function public.school_commercial_leads_search(text,text,integer,integer) to authenticated;
