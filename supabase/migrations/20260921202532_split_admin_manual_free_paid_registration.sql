create or replace function public.admin_manual_free_registration_create(p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = 'pg_catalog', 'public'
as $$
declare
  v_course_id uuid;
  v_course_type text;
begin
  if not public.school_has_permission('edit_students') then
    raise exception 'forbidden' using errcode='42501';
  end if;

  begin
    v_course_id := (p_payload->>'course_id')::uuid;
  exception when others then
    v_course_id := null;
  end;

  if v_course_id is null then
    raise exception 'course_required' using errcode='22023';
  end if;

  select c.type::text
    into v_course_type
  from public.courses c
  where c.id = v_course_id
    and c.active = true;

  if v_course_type is null then
    raise exception 'course_not_found' using errcode='P0002';
  end if;

  if v_course_type <> 'gratuito' then
    raise exception 'course_not_free' using errcode='22023';
  end if;

  return public.admin_manual_registration_create(
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('registration_type','course')
  );
end;
$$;

revoke all on function public.admin_manual_free_registration_create(jsonb) from public, anon;
grant execute on function public.admin_manual_free_registration_create(jsonb) to authenticated, service_role;

create or replace function public.admin_manual_paid_registration_create(p_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = 'pg_catalog', 'public'
as $$
declare
  v_course_id uuid;
  v_course_type text;
begin
  if not public.school_has_permission('edit_students') then
    raise exception 'forbidden' using errcode='42501';
  end if;

  begin
    v_course_id := (p_payload->>'course_id')::uuid;
  exception when others then
    v_course_id := null;
  end;

  if v_course_id is null then
    raise exception 'course_required' using errcode='22023';
  end if;

  select c.type::text
    into v_course_type
  from public.courses c
  where c.id = v_course_id
    and c.active = true;

  if v_course_type is null then
    raise exception 'course_not_found' using errcode='P0002';
  end if;

  if v_course_type <> 'pago' then
    raise exception 'course_not_paid' using errcode='22023';
  end if;

  return public.admin_manual_registration_create(
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object('registration_type','course')
  );
end;
$$;

revoke all on function public.admin_manual_paid_registration_create(jsonb) from public, anon;
grant execute on function public.admin_manual_paid_registration_create(jsonb) to authenticated, service_role;
