-- Live Connect — payment -> automatic enrollment hardening
-- 2026-09-02

create or replace function public.portal_course_auto_enrollment_ready(p_course_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','public','private'
as $$
  select exists (
    select 1
    from public.courses c
    join public.portal_formation_catalog f
      on private.portal_name_key(f.formation_name)=private.portal_name_key(c.name)
    join public.portal_formation_module_ouro_map m
      on m.formation_slug=f.formation_slug
    where c.id=p_course_id
      and c.active=true
      and c.type='pago'
      and coalesce(m.ouro_course_id,'') ~ '^[0-9]+$'
  )
$$;

revoke all on function public.portal_course_auto_enrollment_ready(uuid)
  from public, anon, authenticated;
grant execute on function public.portal_course_auto_enrollment_ready(uuid)
  to service_role;

create or replace function public.sync_lead_status_when_enrollment_completed()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
begin
  if new.status in ('matriculada_ouro','matriculada_manual')
     and (tg_op='INSERT' or old.status is distinct from new.status) then
    update public.leads
       set status='matricula_confirmada',
           archived=false,
           updated_at=now()
     where id=new.lead_id
       and deleted_at is null;
  end if;
  return new;
end
$$;

drop trigger if exists trg_sync_lead_status_when_enrollment_completed
  on public.portal_enrollment_queue;

create trigger trg_sync_lead_status_when_enrollment_completed
after insert or update of status
on public.portal_enrollment_queue
for each row
execute function public.sync_lead_status_when_enrollment_completed();

revoke all on function public.sync_lead_status_when_enrollment_completed()
  from public, anon, authenticated;
