-- Equal administrative privileges with immutable principal profile.
-- Monique remains technically distinguishable in the backend, but has the same effective privileges.
-- The principal profile can never be deleted, deactivated or demoted.

create or replace function public.is_master_admin()
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','public'
as $$
  select coalesce(
    public.current_user_role() in ('master_admin'::public.user_role,'coadmin'::public.user_role),
    false
  )
$$;

create or replace function public.school_my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public'
as $$
declare r public.user_role; a boolean; own boolean;
begin
  select role,active into r,a from public.profiles where id=auth.uid();
  own:=public.is_owner();
  if r is null or coalesce(a,false)=false then
    return jsonb_build_object('ok',false,'role',coalesce(r::text,'none'));
  end if;
  return jsonb_build_object(
    'ok',true,
    'role',r::text,
    'owner',own,
    'coadmin',r='coadmin'::public.user_role,
    'approval_required',false,
    'master',r in ('master_admin'::public.user_role,'coadmin'::public.user_role),
    'secretaria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'secretaria'::public.user_role),
    'comercial',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'admin_comercial'::public.user_role),
    'diretoria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'diretoria'::public.user_role),
    'readonly',r='readonly'::public.user_role
  );
end
$$;

create or replace function private.protect_owner_profile()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $$
declare owner_id uuid;
begin
  select user_id into owner_id from private.system_owner where singleton=true;
  if old.id=owner_id then
    if tg_op='DELETE' then
      raise exception 'owner_profile_protected' using errcode='42501';
    end if;
    if new.role <> 'master_admin'::public.user_role or coalesce(new.active,false)=false then
      raise exception 'owner_profile_protected' using errcode='42501';
    end if;
  end if;
  return new;
end
$$;

drop trigger if exists trg_protect_owner_profile on public.profiles;
create trigger trg_protect_owner_profile
before update or delete on public.profiles
for each row execute function private.protect_owner_profile();

create or replace function public.school_master_set_profile(p_profile_id uuid,p_role text,p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $$
declare new_role public.user_role; oldrow jsonb; owner_id uuid;
begin
  if not public.is_master_admin() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select user_id into owner_id from private.system_owner where singleton=true;
  if p_profile_id=owner_id and (p_role<>'master_admin' or coalesce(p_active,false)=false) then
    raise exception 'owner_profile_protected' using errcode='42501';
  end if;

  if p_role not in ('master_admin','coadmin','diretoria','admin_comercial','secretaria','readonly') then
    raise exception 'invalid_role' using errcode='22023';
  end if;

  select to_jsonb(p) into oldrow from public.profiles p where p.id=p_profile_id;
  if oldrow is null then raise exception 'profile_not_found' using errcode='P0002'; end if;

  new_role:=p_role::public.user_role;
  update public.profiles set role=new_role,active=p_active,updated_at=now() where id=p_profile_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'profile_access_update','profile',p_profile_id,jsonb_build_object('before',oldrow,'role',p_role,'active',p_active));

  return jsonb_build_object('ok',true,'id',p_profile_id,'role',p_role,'active',p_active);
end
$$;

create or replace function public.admin_hard_delete_lead(p_lead_id uuid)
returns void
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
begin
  if not public.is_master_admin() then raise exception 'Acesso restrito'; end if;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  select auth.uid(),'lead_hard_delete','lead',p_lead_id,jsonb_build_object('before',to_jsonb(l))
  from public.leads l where l.id=p_lead_id;
  delete from public.leads where id=p_lead_id;
end
$$;

create or replace function public.school_commercial_create_campaign(
  p_name text,p_title text,p_short_description text,p_offer_text text,p_public_badge text,
  p_start_date date,p_end_date date,p_priority integer,p_show_home boolean,p_show_course_pages boolean,
  p_show_popup boolean,p_enrollment_fee numeric,p_monthly_fee numeric,p_beauty_surcharge numeric,
  p_apply_pricing boolean,p_replace_public boolean default true,p_installments integer default 12,
  p_fast_track_enabled boolean default true,p_fast_track_benefits jsonb default '[]'::jsonb,
  p_late_fee numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_campaign_id uuid;v_pricing_id uuid;v_code text;v_benefits jsonb;v_late numeric;
begin
  if not public.is_admin_comercial() then raise exception 'not_allowed'; end if;
  if nullif(trim(p_name),'') is null or nullif(trim(p_title),'') is null then raise exception 'campaign_name_title_required'; end if;
  if p_start_date is not null and p_end_date is not null and p_end_date<p_start_date then raise exception 'invalid_campaign_period'; end if;
  if p_apply_pricing and (p_enrollment_fee is null or p_enrollment_fee<0 or p_monthly_fee is null or p_monthly_fee<0) then raise exception 'invalid_pricing'; end if;
  if coalesce(p_installments,0)<1 or p_installments>36 then raise exception 'invalid_installments'; end if;

  select coalesce(p_late_fee,pv.late_fee,0) into v_late
  from public.pricing_versions pv
  where pv.active=true and pv.valid_from<=now() and (pv.valid_until is null or pv.valid_until>now())
  order by pv.valid_from desc limit 1;

  v_late:=coalesce(v_late,p_late_fee,0);
  if v_late<0 then raise exception 'invalid_late_fee'; end if;

  if p_replace_public then
    update public.campaigns set active=false,updated_at=now()
    where active=true and highlight_public=true;
  end if;

  v_benefits=case
    when jsonb_typeof(p_fast_track_benefits)='array' and jsonb_array_length(p_fast_track_benefits)>0 then p_fast_track_benefits
    else '["Estudo todos os dias, inclusive aos sábados, para acelerar o aprendizado","Isenção da taxa de matrícula","Curso gratuito de bônus","Farda inclusa","Metodologia prática focada em oportunidades profissionais","Desconto nas parcelas","Horário flexível","2 certificados + 1 curso gratuito","Formação acelerada"]'::jsonb
  end;

  if p_apply_pricing then
    insert into public.pricing_versions(enrollment_fee,monthly_fee,beauty_surcharge,installments,late_fee,valid_from,valid_until,active)
    values(p_enrollment_fee,p_monthly_fee,coalesce(p_beauty_surcharge,0),p_installments,v_late,
           coalesce(p_start_date::timestamptz,now()),
           case when p_end_date is null then null else (p_end_date+1)::timestamptz end,true)
    returning id into v_pricing_id;
  end if;

  v_code='portal-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.campaigns(
    name,code,source,medium,target_path,active,title,short_description,offer_text,public_badge,
    cta_label,cta_message,start_date,end_date,highlight_public,show_home,show_course_pages,show_popup,
    priority,enrollment_fee,monthly_fee,beauty_surcharge,installments,late_fee,fast_track_enabled,
    fast_track_benefits,apply_pricing,pricing_version_id
  )
  values(
    trim(p_name),v_code,'portal_admin','site','/',true,trim(p_title),nullif(trim(p_short_description),''),
    nullif(trim(p_offer_text),''),coalesce(nullif(trim(p_public_badge),''),'OFERTA'),
    'Quero aproveitar','Olá! Quero aproveitar a campanha '||trim(p_name)||'.',
    p_start_date,p_end_date,true,coalesce(p_show_home,true),coalesce(p_show_course_pages,true),
    coalesce(p_show_popup,false),coalesce(p_priority,10),p_enrollment_fee,p_monthly_fee,p_beauty_surcharge,
    p_installments,v_late,coalesce(p_fast_track_enabled,true),v_benefits,coalesce(p_apply_pricing,false),v_pricing_id
  )
  returning id into v_campaign_id;

  return jsonb_build_object('campaign_id',v_campaign_id,'pricing_version_id',v_pricing_id,'code',v_code,'installments',p_installments,'late_fee',v_late,'fast_track_enabled',p_fast_track_enabled);
end
$$;

create or replace function public.school_commercial_set_campaign_active(p_campaign_id uuid,p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_pricing uuid;
begin
  if not public.is_admin_comercial() then raise exception 'not_allowed'; end if;
  update public.campaigns set active=p_active,updated_at=now()
  where id=p_campaign_id
  returning pricing_version_id into v_pricing;
  if not found then raise exception 'campaign_not_found'; end if;
  if v_pricing is not null then update public.pricing_versions set active=p_active where id=v_pricing; end if;
  return jsonb_build_object('campaign_id',p_campaign_id,'active',p_active,'pricing_version_id',v_pricing);
end
$$;

drop trigger if exists trg_coadmin_pricing_approval on public.pricing_versions;
drop trigger if exists trg_coadmin_site_settings_approval on public.site_settings;
drop trigger if exists trg_coadmin_contract_templates_approval on public.contract_templates;

do $$
declare t text;
begin
  foreach t in array array[
    'campaigns','classes','commercial_goals','contracts','course_categories','courses','enrollments',
    'followups','lead_activities','lead_interests','lead_notes','leads','message_templates','notifications',
    'payments','reports','waiting_list'
  ]
  loop
    execute format('drop trigger if exists trg_coadmin_delete_approval on public.%I',t);
  end loop;
end
$$;

update public.profiles
set full_name='Leonardo Couto',role='master_admin'::public.user_role,active=true,updated_at=now()
where id=(select user_id from private.system_owner where singleton=true);

update public.profiles
set full_name='Monique Gomes',role='coadmin'::public.user_role,active=true,updated_at=now()
where id='42126430-9593-40ee-9ef1-5380842f6fb0'::uuid;
