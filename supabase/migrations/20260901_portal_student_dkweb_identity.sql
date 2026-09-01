create or replace function public.portal_student_dkweb_identity(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog', 'public', 'private'
as $function$
declare
  v_session public.student_portal_sessions%rowtype;
  v_api jsonb;
  v_student jsonb;
  v_cpf text;
begin
  select * into v_session
  from public.student_portal_sessions
  where token_hash = p_token_hash
    and revoked_at is null
    and expires_at > now()
  limit 1;

  if v_session.id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session');
  end if;

  v_api := private.ouro_api_student_by_login(v_session.login);
  if coalesce((v_api->>'ok')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'error', 'ouro_identity_unavailable');
  end if;

  v_student := v_api->'student';
  v_cpf := regexp_replace(coalesce(v_student->>'cpf', ''), '\\D', '', 'g');

  if length(v_cpf) <> 11 then
    return jsonb_build_object('ok', false, 'error', 'ouro_identity_incomplete');
  end if;

  return jsonb_build_object(
    'ok', true,
    'subject', coalesce(v_student->>'id', v_session.ouro_student_id),
    'cpf', v_cpf
  );
end;
$function$;

revoke all on function public.portal_student_dkweb_identity(text) from public;
revoke all on function public.portal_student_dkweb_identity(text) from anon;
revoke all on function public.portal_student_dkweb_identity(text) from authenticated;
grant execute on function public.portal_student_dkweb_identity(text) to service_role;

comment on function public.portal_student_dkweb_identity(text) is
  'Internal service-role-only resolver for linking an active Ouro portal session to DKWeb by CPF.';
