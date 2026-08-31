create table if not exists private.system_owner (
  singleton boolean primary key default true check (singleton),
  user_id uuid not null unique references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into private.system_owner(singleton,user_id)
values (true,'62e02abd-0e94-40e1-9364-3b2c5f80dbed'::uuid)
on conflict (singleton) do update set user_id=excluded.user_id,updated_at=now();

revoke all on private.system_owner from public,anon,authenticated;

create table if not exists public.admin_approval_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  entity_type text,
  entity_id uuid,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','approved','rejected','executed','failed','cancelled')),
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  executed_at timestamptz,
  execution_result jsonb,
  execution_error text
);

alter table public.admin_approval_requests enable row level security;
revoke all on public.admin_approval_requests from anon;
grant select on public.admin_approval_requests to authenticated;

drop policy if exists "approval requester or owner read" on public.admin_approval_requests;
create policy "approval requester or owner read"
on public.admin_approval_requests for select
to authenticated
using (
  requester_id=(select auth.uid())
  or exists(select 1 from private.system_owner o where o.user_id=(select auth.uid()))
);

create index if not exists admin_approval_requests_status_requested_idx
on public.admin_approval_requests(status,requested_at desc);

create or replace function public.is_owner()
returns boolean language sql stable security definer
set search_path='pg_catalog','private'
as $$select coalesce(exists(select 1 from private.system_owner o where o.user_id=auth.uid()),false)$$;

create or replace function public.is_coadmin()
returns boolean language sql stable security definer
set search_path='pg_catalog','public'
as $$select coalesce(public.current_user_role()='coadmin'::public.user_role,false)$$;

create or replace function public.is_admin_comercial()
returns boolean language sql stable security definer
set search_path='pg_catalog','public'
as $$select coalesce(public.current_user_role() in ('master_admin'::public.user_role,'coadmin'::public.user_role,'admin_comercial'::public.user_role),false)$$;

create or replace function public.is_secretaria()
returns boolean language sql stable security definer
set search_path='pg_catalog','public'
as $$select coalesce(public.current_user_role() in ('master_admin'::public.user_role,'coadmin'::public.user_role,'secretaria'::public.user_role),false)$$;

create or replace function public.is_diretoria()
returns boolean language sql stable security definer
set search_path='pg_catalog','public'
as $$select coalesce(public.current_user_role() in ('master_admin'::public.user_role,'coadmin'::public.user_role,'diretoria'::public.user_role),false)$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer
set search_path='pg_catalog','public'
as $$
select exists(
  select 1 from public.profiles p
  where p.id=auth.uid() and p.active=true
    and p.role in ('master_admin'::public.user_role,'coadmin'::public.user_role,'diretoria'::public.user_role,'admin_comercial'::public.user_role,'secretaria'::public.user_role,'readonly'::public.user_role)
)
$$;

create or replace function public.school_my_access()
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public'
as $$
declare r public.user_role; a boolean; own boolean;
begin
  select role,active into r,a from public.profiles where id=auth.uid();
  own:=public.is_owner();
  if r is null or coalesce(a,false)=false then return jsonb_build_object('ok',false,'role',coalesce(r::text,'none')); end if;
  return jsonb_build_object(
    'ok',true,'role',r::text,'owner',own,'coadmin',r='coadmin'::public.user_role,
    'approval_required',r='coadmin'::public.user_role,
    'master',r in ('master_admin'::public.user_role,'coadmin'::public.user_role),
    'secretaria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'secretaria'::public.user_role),
    'comercial',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'admin_comercial'::public.user_role),
    'diretoria',r in ('master_admin'::public.user_role,'coadmin'::public.user_role,'diretoria'::public.user_role),
    'readonly',r='readonly'::public.user_role
  );
end
$$;

create or replace function public.school_request_critical_action(p_action text,p_entity_type text default null,p_entity_id uuid default null,p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer
set search_path='pg_catalog','public'
as $$
declare rid uuid;
begin
  if not public.is_coadmin() then raise exception 'approval_request_only_for_coadmin' using errcode='42501'; end if;
  if nullif(trim(p_action),'') is null then raise exception 'action_required' using errcode='22023'; end if;
  insert into public.admin_approval_requests(requester_id,action,entity_type,entity_id,payload)
  values(auth.uid(),trim(p_action),nullif(trim(p_entity_type),''),p_entity_id,coalesce(p_payload,'{}'::jsonb))
  returning id into rid;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'critical_action_requested',coalesce(nullif(trim(p_entity_type),''),'approval'),p_entity_id,jsonb_build_object('request_id',rid,'requested_action',trim(p_action)));
  return rid;
end
$$;
revoke all on function public.school_request_critical_action(text,text,uuid,jsonb) from public,anon;
grant execute on function public.school_request_critical_action(text,text,uuid,jsonb) to authenticated;

create or replace function private.protect_owner_profile()
returns trigger language plpgsql security definer
set search_path='pg_catalog','private','public'
as $$
declare owner_id uuid;
begin
  select user_id into owner_id from private.system_owner where singleton=true;
  if old.id=owner_id and auth.uid() is not null and auth.uid()<>owner_id then
    raise exception 'owner_profile_protected' using errcode='42501';
  end if;
  return case when tg_op='DELETE' then old else new end;
end
$$;

drop trigger if exists trg_protect_owner_profile on public.profiles;
create trigger trg_protect_owner_profile before update or delete on public.profiles
for each row execute function private.protect_owner_profile();

create or replace function public.school_master_profiles()
returns table(id uuid,full_name text,role text,active boolean,last_seen_at timestamptz,created_at timestamptz)
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $$
begin
  if not (public.is_owner() or public.is_coadmin()) then raise exception 'forbidden' using errcode='42501'; end if;
  return query select p.id,p.full_name,p.role::text,p.active,p.last_seen_at,p.created_at from public.profiles p order by p.full_name;
end
$$;

create or replace function public.school_master_set_profile(p_profile_id uuid,p_role text,p_active boolean)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare new_role public.user_role; oldrow jsonb; rid uuid; owner_id uuid;
begin
  if not (public.is_owner() or public.is_coadmin()) then raise exception 'forbidden' using errcode='42501'; end if;
  select user_id into owner_id from private.system_owner where singleton=true;
  if p_profile_id=owner_id and not public.is_owner() then raise exception 'owner_profile_protected' using errcode='42501'; end if;
  if p_profile_id=auth.uid() and public.is_owner() and (p_role<>'master_admin' or p_active=false) then raise exception 'master_self_lockout_blocked' using errcode='22023'; end if;
  if p_role not in ('master_admin','coadmin','diretoria','admin_comercial','secretaria','readonly') then raise exception 'invalid_role' using errcode='22023'; end if;
  select to_jsonb(p) into oldrow from public.profiles p where p.id=p_profile_id;
  if oldrow is null then raise exception 'profile_not_found' using errcode='P0002'; end if;
  if public.is_coadmin() then
    rid:=public.school_request_critical_action('profile_access_update','profile',p_profile_id,jsonb_build_object('role',p_role,'active',p_active));
    return jsonb_build_object('ok',true,'pending_approval',true,'request_id',rid);
  end if;
  new_role:=p_role::public.user_role;
  update public.profiles set role=new_role,active=p_active,updated_at=now() where id=p_profile_id;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'profile_access_update','profile',p_profile_id,jsonb_build_object('before',oldrow,'role',p_role,'active',p_active));
  return jsonb_build_object('ok',true,'id',p_profile_id,'role',p_role,'active',p_active);
end
$$;

create or replace function public.admin_hard_delete_lead(p_lead_id uuid)
returns void language plpgsql security definer
set search_path='pg_catalog','public'
as $$
declare rid uuid;
begin
  if public.is_coadmin() then
    rid:=public.school_request_critical_action('lead_hard_delete','lead',p_lead_id,'{}'::jsonb);
    return;
  end if;
  if not public.is_owner() then raise exception 'Acesso restrito ao proprietário'; end if;
  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  select auth.uid(),'lead_hard_delete','lead',p_lead_id,jsonb_build_object('before',to_jsonb(l)) from public.leads l where l.id=p_lead_id;
  delete from public.leads where id=p_lead_id;
end
$$;

create or replace function private.queue_coadmin_sensitive_dml()
returns trigger language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare rid uuid; p jsonb;
begin
  if not public.is_coadmin() then return case when tg_op='DELETE' then old else new end; end if;
  p:=jsonb_build_object('table',tg_table_name,'op',tg_op,'old',case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,'new',case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end);
  rid:=public.school_request_critical_action('sensitive_dml',tg_table_name,null,p);
  return null;
end
$$;

drop trigger if exists trg_coadmin_pricing_approval on public.pricing_versions;
create trigger trg_coadmin_pricing_approval before insert or update or delete on public.pricing_versions for each row execute function private.queue_coadmin_sensitive_dml();
drop trigger if exists trg_coadmin_site_settings_approval on public.site_settings;
create trigger trg_coadmin_site_settings_approval before insert or update or delete on public.site_settings for each row execute function private.queue_coadmin_sensitive_dml();
drop trigger if exists trg_coadmin_contract_templates_approval on public.contract_templates;
create trigger trg_coadmin_contract_templates_approval before insert or update or delete on public.contract_templates for each row execute function private.queue_coadmin_sensitive_dml();

create or replace function private.execute_sensitive_dml(p jsonb)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare t text:=p->>'table'; op text:=upper(p->>'op'); o jsonb:=p->'old'; n jsonb:=p->'new';
begin
  if not public.is_owner() then raise exception 'owner_only' using errcode='42501'; end if;
  if t='pricing_versions' then
    if op='INSERT' then
      insert into public.pricing_versions(id,enrollment_fee,monthly_fee,beauty_surcharge,valid_from,valid_until,active,created_at,installments,late_fee)
      values((n->>'id')::uuid,(n->>'enrollment_fee')::numeric,(n->>'monthly_fee')::numeric,coalesce((n->>'beauty_surcharge')::numeric,40),(n->>'valid_from')::timestamptz,nullif(n->>'valid_until','')::timestamptz,coalesce((n->>'active')::boolean,true),(n->>'created_at')::timestamptz,coalesce((n->>'installments')::integer,12),coalesce((n->>'late_fee')::numeric,0));
    elsif op='UPDATE' then
      update public.pricing_versions set enrollment_fee=(n->>'enrollment_fee')::numeric,monthly_fee=(n->>'monthly_fee')::numeric,beauty_surcharge=coalesce((n->>'beauty_surcharge')::numeric,40),valid_from=(n->>'valid_from')::timestamptz,valid_until=nullif(n->>'valid_until','')::timestamptz,active=coalesce((n->>'active')::boolean,true),installments=coalesce((n->>'installments')::integer,12),late_fee=coalesce((n->>'late_fee')::numeric,0) where id=(o->>'id')::uuid;
    elsif op='DELETE' then delete from public.pricing_versions where id=(o->>'id')::uuid;
    else raise exception 'unsupported_sensitive_op'; end if;
  elsif t='site_settings' then
    if op='INSERT' then insert into public.site_settings(key,value,updated_at) values(n->>'key',n->'value',coalesce((n->>'updated_at')::timestamptz,now()));
    elsif op='UPDATE' then update public.site_settings set key=n->>'key',value=n->'value',updated_at=coalesce((n->>'updated_at')::timestamptz,now()) where key=o->>'key';
    elsif op='DELETE' then delete from public.site_settings where key=o->>'key';
    else raise exception 'unsupported_sensitive_op'; end if;
  elsif t='contract_templates' then
    if op='INSERT' then insert into public.contract_templates(id,name,version,content,active,created_at) values((n->>'id')::uuid,n->>'name',(n->>'version')::integer,n->>'content',coalesce((n->>'active')::boolean,false),(n->>'created_at')::timestamptz);
    elsif op='UPDATE' then update public.contract_templates set name=n->>'name',version=(n->>'version')::integer,content=n->>'content',active=coalesce((n->>'active')::boolean,false) where id=(o->>'id')::uuid;
    elsif op='DELETE' then delete from public.contract_templates where id=(o->>'id')::uuid;
    else raise exception 'unsupported_sensitive_op'; end if;
  else raise exception 'unsupported_sensitive_table:%',t; end if;
  return jsonb_build_object('table',t,'op',op,'executed',true);
end
$$;
revoke all on function private.execute_sensitive_dml(jsonb) from public,anon,authenticated;

create or replace function public.school_owner_approval_queue(p_status text default 'pending',p_limit integer default 100)
returns table(request_id uuid,requester_id uuid,requester_name text,action text,entity_type text,entity_id uuid,payload jsonb,status text,requested_at timestamptz,decided_at timestamptz,decision_note text)
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $$
begin
  if not public.is_owner() then raise exception 'owner_only' using errcode='42501'; end if;
  return query
  select r.id,r.requester_id,p.full_name,r.action,r.entity_type,r.entity_id,r.payload,r.status,r.requested_at,r.decided_at,r.decision_note
  from public.admin_approval_requests r left join public.profiles p on p.id=r.requester_id
  where p_status is null or r.status=p_status
  order by r.requested_at desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end
$$;

create or replace function public.school_owner_decide_approval(p_request_id uuid,p_approve boolean,p_note text default null)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v public.admin_approval_requests%rowtype; result jsonb:='{}'::jsonb;
begin
  if not public.is_owner() then raise exception 'owner_only' using errcode='42501'; end if;
  select * into v from public.admin_approval_requests where id=p_request_id for update;
  if not found then raise exception 'approval_not_found' using errcode='P0002'; end if;
  if v.status<>'pending' then raise exception 'approval_already_decided' using errcode='22023'; end if;

  if not coalesce(p_approve,false) then
    update public.admin_approval_requests set status='rejected',decided_by=auth.uid(),decided_at=now(),decision_note=nullif(trim(p_note),'') where id=p_request_id;
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'critical_action_rejected',coalesce(v.entity_type,'approval'),v.entity_id,jsonb_build_object('request_id',v.id,'requested_action',v.action,'requester_id',v.requester_id));
    return jsonb_build_object('ok',true,'status','rejected','request_id',v.id);
  end if;

  update public.admin_approval_requests set status='approved',decided_by=auth.uid(),decided_at=now(),decision_note=nullif(trim(p_note),'') where id=p_request_id;
  begin
    if v.action='profile_access_update' then
      result:=public.school_master_set_profile(v.entity_id,v.payload->>'role',coalesce((v.payload->>'active')::boolean,true));
    elsif v.action='lead_hard_delete' then
      perform public.admin_hard_delete_lead(v.entity_id); result:=jsonb_build_object('deleted',true,'lead_id',v.entity_id);
    elsif v.action='campaign_toggle_sensitive' then
      result:=public.school_commercial_set_campaign_active(v.entity_id,coalesce((v.payload->>'active')::boolean,false));
    elsif v.action='campaign_create_sensitive' then
      result:=public.school_commercial_create_campaign(
        v.payload->>'name',v.payload->>'title',v.payload->>'short_description',v.payload->>'offer_text',v.payload->>'public_badge',
        nullif(v.payload->>'start_date','')::date,nullif(v.payload->>'end_date','')::date,coalesce((v.payload->>'priority')::integer,10),
        coalesce((v.payload->>'show_home')::boolean,true),coalesce((v.payload->>'show_course_pages')::boolean,true),coalesce((v.payload->>'show_popup')::boolean,false),
        nullif(v.payload->>'enrollment_fee','')::numeric,nullif(v.payload->>'monthly_fee','')::numeric,nullif(v.payload->>'beauty_surcharge','')::numeric,
        coalesce((v.payload->>'apply_pricing')::boolean,false),coalesce((v.payload->>'replace_public')::boolean,true),coalesce((v.payload->>'installments')::integer,12),
        coalesce((v.payload->>'fast_track_enabled')::boolean,true),coalesce(v.payload->'fast_track_benefits','[]'::jsonb),nullif(v.payload->>'late_fee','')::numeric
      );
    elsif v.action='sensitive_dml' then
      result:=private.execute_sensitive_dml(v.payload);
    else raise exception 'unsupported_approval_action:%',v.action; end if;

    update public.admin_approval_requests set status='executed',executed_at=now(),execution_result=result,execution_error=null where id=p_request_id;
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'critical_action_approved',coalesce(v.entity_type,'approval'),v.entity_id,jsonb_build_object('request_id',v.id,'requested_action',v.action,'requester_id',v.requester_id));
    return jsonb_build_object('ok',true,'status','executed','request_id',v.id,'result',result);
  exception when others then
    update public.admin_approval_requests set status='failed',executed_at=now(),execution_error=left(sqlerrm,500) where id=p_request_id;
    raise;
  end;
end
$$;

revoke all on function public.school_owner_approval_queue(text,integer) from public,anon;
grant execute on function public.school_owner_approval_queue(text,integer) to authenticated;
revoke all on function public.school_owner_decide_approval(uuid,boolean,text) from public,anon;
grant execute on function public.school_owner_decide_approval(uuid,boolean,text) to authenticated;

create or replace function public.school_commercial_create_campaign(
  p_name text,p_title text,p_short_description text,p_offer_text text,p_public_badge text,p_start_date date,p_end_date date,p_priority integer,
  p_show_home boolean,p_show_course_pages boolean,p_show_popup boolean,p_enrollment_fee numeric,p_monthly_fee numeric,p_beauty_surcharge numeric,p_apply_pricing boolean,
  p_replace_public boolean default true,p_installments integer default 12,p_fast_track_enabled boolean default true,p_fast_track_benefits jsonb default '[]'::jsonb,p_late_fee numeric default null
)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public'
as $$
declare v_campaign_id uuid;v_pricing_id uuid;v_code text;v_benefits jsonb;v_late numeric;rid uuid;
begin
  if not public.is_admin_comercial() then raise exception 'not_allowed'; end if;
  if nullif(trim(p_name),'') is null or nullif(trim(p_title),'') is null then raise exception 'campaign_name_title_required'; end if;
  if p_start_date is not null and p_end_date is not null and p_end_date<p_start_date then raise exception 'invalid_campaign_period'; end if;
  if p_apply_pricing and (p_enrollment_fee is null or p_enrollment_fee<0 or p_monthly_fee is null or p_monthly_fee<0) then raise exception 'invalid_pricing'; end if;
  if coalesce(p_installments,0)<1 or p_installments>36 then raise exception 'invalid_installments'; end if;
  if public.is_coadmin() and (coalesce(p_apply_pricing,false) or coalesce(p_replace_public,false)) then
    rid:=public.school_request_critical_action('campaign_create_sensitive','campaign',null,jsonb_build_object(
      'name',p_name,'title',p_title,'short_description',p_short_description,'offer_text',p_offer_text,'public_badge',p_public_badge,'start_date',p_start_date,'end_date',p_end_date,
      'priority',p_priority,'show_home',p_show_home,'show_course_pages',p_show_course_pages,'show_popup',p_show_popup,'enrollment_fee',p_enrollment_fee,'monthly_fee',p_monthly_fee,
      'beauty_surcharge',p_beauty_surcharge,'apply_pricing',p_apply_pricing,'replace_public',p_replace_public,'installments',p_installments,'fast_track_enabled',p_fast_track_enabled,
      'fast_track_benefits',p_fast_track_benefits,'late_fee',p_late_fee
    ));
    return jsonb_build_object('ok',true,'pending_approval',true,'request_id',rid);
  end if;
  select coalesce(p_late_fee,pv.late_fee,0) into v_late from public.pricing_versions pv where pv.active=true and pv.valid_from<=now() and (pv.valid_until is null or pv.valid_until>now()) order by pv.valid_from desc limit 1;
  v_late:=coalesce(v_late,p_late_fee,0); if v_late<0 then raise exception 'invalid_late_fee'; end if;
  if p_replace_public then update public.campaigns set active=false,updated_at=now() where active=true and highlight_public=true; end if;
  v_benefits=case when jsonb_typeof(p_fast_track_benefits)='array' and jsonb_array_length(p_fast_track_benefits)>0 then p_fast_track_benefits else '["Estudo todos os dias, inclusive aos sábados, para acelerar o aprendizado","Isenção da taxa de matrícula","Curso gratuito de bônus","Farda inclusa","Metodologia prática focada em oportunidades profissionais","Desconto nas parcelas","Horário flexível","2 certificados + 1 curso gratuito","Formação acelerada"]'::jsonb end;
  if p_apply_pricing then
    insert into public.pricing_versions(enrollment_fee,monthly_fee,beauty_surcharge,installments,late_fee,valid_from,valid_until,active)
    values(p_enrollment_fee,p_monthly_fee,coalesce(p_beauty_surcharge,0),p_installments,v_late,coalesce(p_start_date::timestamptz,now()),case when p_end_date is null then null else (p_end_date+1)::timestamptz end,true)
    returning id into v_pricing_id;
  end if;
  v_code='portal-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.campaigns(name,code,source,medium,target_path,active,title,short_description,offer_text,public_badge,cta_label,cta_message,start_date,end_date,highlight_public,show_home,show_course_pages,show_popup,priority,enrollment_fee,monthly_fee,beauty_surcharge,installments,late_fee,fast_track_enabled,fast_track_benefits,apply_pricing,pricing_version_id)
  values(trim(p_name),v_code,'portal_admin','site','/',true,trim(p_title),nullif(trim(p_short_description),''),nullif(trim(p_offer_text),''),coalesce(nullif(trim(p_public_badge),''),'OFERTA'),'Quero aproveitar','Olá! Quero aproveitar a campanha '||trim(p_name)||'.',p_start_date,p_end_date,true,coalesce(p_show_home,true),coalesce(p_show_course_pages,true),coalesce(p_show_popup,false),coalesce(p_priority,10),p_enrollment_fee,p_monthly_fee,p_beauty_surcharge,p_installments,v_late,coalesce(p_fast_track_enabled,true),v_benefits,coalesce(p_apply_pricing,false),v_pricing_id)
  returning id into v_campaign_id;
  return jsonb_build_object('campaign_id',v_campaign_id,'pricing_version_id',v_pricing_id,'code',v_code,'installments',p_installments,'late_fee',v_late,'fast_track_enabled',p_fast_track_enabled);
end
$$;

create or replace function public.school_commercial_set_campaign_active(p_campaign_id uuid,p_active boolean)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public'
as $$
declare v_pricing uuid;v_public boolean;rid uuid;
begin
  if not public.is_admin_comercial() then raise exception 'not_allowed'; end if;
  select pricing_version_id,highlight_public into v_pricing,v_public from public.campaigns where id=p_campaign_id;
  if not found then raise exception 'campaign_not_found'; end if;
  if public.is_coadmin() and (v_pricing is not null or coalesce(v_public,false)) then
    rid:=public.school_request_critical_action('campaign_toggle_sensitive','campaign',p_campaign_id,jsonb_build_object('active',p_active));
    return jsonb_build_object('ok',true,'pending_approval',true,'request_id',rid);
  end if;
  update public.campaigns set active=p_active,updated_at=now() where id=p_campaign_id returning pricing_version_id into v_pricing;
  if v_pricing is not null then update public.pricing_versions set active=p_active where id=v_pricing; end if;
  return jsonb_build_object('campaign_id',p_campaign_id,'active',p_active,'pricing_version_id',v_pricing);
end
$$;

update public.profiles
set full_name='Monique Gomes',role='coadmin'::public.user_role,active=true,updated_at=now()
where id='42126430-9593-40ee-9ef1-5380842f6fb0'::uuid;
