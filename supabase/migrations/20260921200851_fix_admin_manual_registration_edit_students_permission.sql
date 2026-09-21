do $$
declare
  v_def text;
  v_old constant text := 'if not public.is_admin_comercial() then';
  v_new constant text := 'if not public.school_has_permission(''edit_students'') then';
begin
  select pg_get_functiondef('public.admin_manual_registration_create(jsonb)'::regprocedure)
    into v_def;

  if position(v_new in v_def) > 0 then
    return;
  end if;

  if position(v_old in v_def) = 0 then
    raise exception 'unexpected admin_manual_registration_create authorization clause';
  end if;

  v_def := replace(v_def, v_old, v_new);
  execute v_def;
end
$$;
