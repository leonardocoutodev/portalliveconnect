-- Jovem Aprendiz: persistência da turma escolhida
-- 2026-09-02

create or replace function public.school_commercial_set_young_apprentice_class(
  p_form_id uuid,
  p_selected_class text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  v_label text;
  v_interest_id uuid;
  v_out jsonb;
begin
  if not public.is_admin_comercial() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  v_label := case p_selected_class
    when 'terca_0900_1000' then 'Terça-feira • 09:00 às 10:00'
    when 'quinta_1400_1500' then 'Quinta-feira • 14:00 às 15:00'
    else null
  end;

  if v_label is null then
    raise exception 'invalid_selected_class' using errcode='22023';
  end if;

  update public.young_apprentice_registration_forms f
     set data_snapshot = coalesce(f.data_snapshot,'{}'::jsonb)
                         || jsonb_build_object(
                              'selected_class',p_selected_class,
                              'selected_class_label',v_label
                            ),
         updated_at = now()
   where f.id = p_form_id
  returning f.interest_id,to_jsonb(f) into v_interest_id,v_out;

  if v_out is null then
    raise exception 'form_not_found' using errcode='P0002';
  end if;

  update public.lead_interests li
     set metadata = coalesce(li.metadata,'{}'::jsonb)
                    || jsonb_build_object(
                         'selected_class',p_selected_class,
                         'selected_class_label',v_label
                       )
   where li.id = v_interest_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    'young_apprentice_class_updated',
    'young_apprentice_form',
    p_form_id,
    jsonb_build_object(
      'selected_class',p_selected_class,
      'selected_class_label',v_label
    )
  );

  return v_out;
end
$$;

revoke all on function public.school_commercial_set_young_apprentice_class(uuid,text)
  from public,anon;
grant execute on function public.school_commercial_set_young_apprentice_class(uuid,text)
  to authenticated;
