-- Live Connect internal chat: messenger-style pairwise privacy and silent owner supervision

update public.school_chat_channels
set channel_type='public',participant_roles='{}'::text[],active=true,sort_order=10,
    description='Comunicação geral entre toda a equipe da escola.',updated_at=now()
where slug='geral';

update public.school_chat_channels
set active=false,updated_at=now()
where slug in ('comercial','administracao','secretaria','diretoria');

insert into public.school_chat_channels(slug,name,description,active,sort_order,channel_type,participant_roles)
values
  ('priv-comercial-administracao','Comercial ↔ Administração','Conversa privada entre Comercial e Administração.',true,20,'private',array['admin_comercial','coadmin']::text[]),
  ('priv-comercial-secretaria','Comercial ↔ Secretaria','Conversa privada entre Comercial e Secretaria.',true,30,'private',array['admin_comercial','secretaria']::text[]),
  ('priv-comercial-diretoria','Comercial ↔ Diretoria','Conversa privada entre Comercial e Diretoria.',true,40,'private',array['admin_comercial','diretoria']::text[]),
  ('priv-administracao-secretaria','Administração ↔ Secretaria','Conversa privada entre Administração e Secretaria.',true,50,'private',array['coadmin','secretaria']::text[]),
  ('priv-administracao-diretoria','Administração ↔ Diretoria','Conversa privada entre Administração e Diretoria.',true,60,'private',array['coadmin','diretoria']::text[]),
  ('priv-secretaria-diretoria','Secretaria ↔ Diretoria','Conversa privada entre Secretaria e Diretoria.',true,70,'private',array['secretaria','diretoria']::text[])
on conflict(slug) do update set
  name=excluded.name,description=excluded.description,active=true,sort_order=excluded.sort_order,
  channel_type='private',participant_roles=excluded.participant_roles,updated_at=now();

create or replace function public.school_chat_people()
returns table(user_id uuid,full_name text,chat_key text,department text,presence text)
language plpgsql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
begin
  if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
  select p.id,coalesce(p.full_name,'Equipe Live Connect'),
    case
      when exists(select 1 from private.system_owner o where o.user_id=p.id) then 'comercial'
      when p.role::text='admin_comercial' then 'comercial'
      when p.role::text='coadmin' then 'administracao'
      when p.role::text='secretaria' then 'secretaria'
      when p.role::text='diretoria' then 'diretoria'
      else p.role::text
    end,
    case
      when exists(select 1 from private.system_owner o where o.user_id=p.id) then 'Comercial'
      when p.role::text='admin_comercial' then 'Comercial'
      when p.role::text='coadmin' then 'Administração'
      when p.role::text='secretaria' then 'Secretaria'
      when p.role::text='diretoria' then 'Diretoria'
      else 'Equipe'
    end,
    case
      when pr.status='offline' then 'offline'
      when pr.last_seen_at>=now()-interval '45 seconds' then 'online'
      when pr.last_seen_at>=now()-interval '5 minutes' then 'away'
      else 'offline'
    end
  from public.profiles p
  left join public.school_chat_presence pr on pr.user_id=p.id
  where p.active=true and p.role::text in ('master_admin','admin_comercial','coadmin','secretaria','diretoria')
  order by p.full_name;
end
$$;

revoke all on function public.school_chat_people() from public,anon;
grant execute on function public.school_chat_people() to authenticated,service_role;

create or replace function public.school_chat_presence_list(p_channel_id uuid)
returns table(user_id uuid,full_name text,role text,presence text,is_typing boolean,last_seen_at timestamptz)
language plpgsql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
declare v_type text;v_roles text[];
begin
  if not public.school_chat_can_access(p_channel_id,false) then raise exception 'channel_not_found' using errcode='P0002'; end if;
  select c.channel_type,c.participant_roles into v_type,v_roles
  from public.school_chat_channels c where c.id=p_channel_id and c.active=true;
  return query
  select p.id,p.full_name,
    case when exists(select 1 from private.system_owner o where o.user_id=p.id) then 'admin_comercial' else p.role::text end,
    case
      when pr.status='offline' then 'offline'
      when pr.last_seen_at>=now()-interval '45 seconds' then 'online'
      when pr.last_seen_at>=now()-interval '5 minutes' then 'away'
      else 'offline'
    end,
    coalesce(pr.typing_channel_id=p_channel_id and pr.typing_until>now(),false),
    pr.last_seen_at
  from public.profiles p
  left join public.school_chat_presence pr on pr.user_id=p.id
  where p.active=true and p.role<>'readonly'
    and (
      v_type='public'
      or p.role::text=any(v_roles)
      or (exists(select 1 from private.system_owner o where o.user_id=p.id) and 'admin_comercial'=any(v_roles))
    )
  order by p.full_name;
end
$$;

create or replace function public.school_chat_message_receipts(p_message_id uuid)
returns table(user_id uuid,full_name text,read_at timestamptz)
language plpgsql stable security definer
set search_path to 'pg_catalog','public','private'
as $$
declare cid uuid;created timestamptz;v_type text;v_roles text[];
begin
  select m.channel_id,m.created_at into cid,created
  from public.school_chat_messages m where m.id=p_message_id and m.deleted_at is null;
  if cid is null or not public.school_chat_can_access(cid,false) then raise exception 'message_not_found' using errcode='P0002'; end if;
  select c.channel_type,c.participant_roles into v_type,v_roles from public.school_chat_channels c where c.id=cid;
  return query
  select r.user_id,p.full_name,r.last_read_at
  from public.school_chat_reads r join public.profiles p on p.id=r.user_id
  where r.channel_id=cid and r.last_read_at>=created
    and (v_type='public' or not exists(select 1 from private.system_owner o where o.user_id=r.user_id) or 'admin_comercial'=any(v_roles))
  order by r.last_read_at desc;
end
$$;
