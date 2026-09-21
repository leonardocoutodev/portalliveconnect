alter function public.admin_manual_ead_direct_enrollment(jsonb)
  rename to admin_manual_ead_direct_enrollment_legacy_v1;

create function public.admin_manual_ead_direct_enrollment(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $$
declare
  v_clean jsonb;
begin
  if not public.school_has_permission('edit_students') then
    raise exception 'forbidden' using errcode='42501';
  end if;

  v_clean := coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
    'whatsapp', regexp_replace(coalesce(p_payload->>'whatsapp',''), '\D', '', 'g'),
    'cpf', regexp_replace(coalesce(p_payload->>'cpf',''), '\D', '', 'g'),
    'zip_code', regexp_replace(coalesce(p_payload->>'zip_code',''), '\D', '', 'g')
  );

  return public.admin_manual_ead_direct_enrollment_legacy_v1(v_clean);
end
$$;

revoke all on function public.admin_manual_ead_direct_enrollment_legacy_v1(jsonb) from public, anon, authenticated;
grant execute on function public.admin_manual_ead_direct_enrollment_legacy_v1(jsonb) to service_role;

revoke all on function public.admin_manual_ead_direct_enrollment(jsonb) from public, anon;
grant execute on function public.admin_manual_ead_direct_enrollment(jsonb) to authenticated, service_role;
