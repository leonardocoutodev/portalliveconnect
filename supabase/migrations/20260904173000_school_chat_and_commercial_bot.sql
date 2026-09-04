create table if not exists public.school_chat_channels (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.school_chat_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.school_chat_channels(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete restrict,
  body text not null check (char_length(body) between 1 and 2500),
  reply_to_id uuid references public.school_chat_messages(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.school_chat_reads (
  channel_id uuid not null references public.school_chat_channels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key(channel_id,user_id)
);
create index if not exists school_chat_messages_channel_created_idx
  on public.school_chat_messages(channel_id,created_at desc) where deleted_at is null;
insert into public.school_chat_channels(slug,name,description,sort_order)
values
 ('geral','Geral','Comunicação entre todos os departamentos da escola.',10),
 ('comercial','Comercial','Leads, visitas, follow-ups, campanhas e matrículas.',20),
 ('secretaria','Secretaria','Matrículas, documentos, turmas, financeiro e operação acadêmica.',30),
 ('diretoria','Diretoria','Gestão, indicadores, decisões e alinhamentos.',40)
on conflict (slug) do update set name=excluded.name,description=excluded.description,sort_order=excluded.sort_order,active=true,updated_at=now();
alter table public.school_chat_channels enable row level security;
alter table public.school_chat_messages enable row level security;
alter table public.school_chat_reads enable row level security;
revoke all on public.school_chat_channels,public.school_chat_messages,public.school_chat_reads from anon,authenticated;
grant all on public.school_chat_channels,public.school_chat_messages,public.school_chat_reads to service_role;

create or replace function public.school_chat_channels()
returns table(channel_id uuid,slug text,name text,description text,unread_count bigint,last_message text,last_message_at timestamptz)
language plpgsql stable security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 return query
 select c.id,c.slug,c.name,c.description,
   count(m.id) filter(where m.created_at>coalesce(r.last_read_at,'epoch'::timestamptz) and m.sender_id<>auth.uid())::bigint,
   lm.body,lm.created_at
 from public.school_chat_channels c
 left join public.school_chat_reads r on r.channel_id=c.id and r.user_id=auth.uid()
 left join public.school_chat_messages m on m.channel_id=c.id and m.deleted_at is null
 left join lateral (
   select mm.body,mm.created_at from public.school_chat_messages mm
   where mm.channel_id=c.id and mm.deleted_at is null order by mm.created_at desc limit 1
 ) lm on true
 where c.active=true
 group by c.id,c.slug,c.name,c.description,c.sort_order,r.last_read_at,lm.body,lm.created_at
 order by c.sort_order,c.name;
end $$;

create or replace function public.school_chat_messages(p_channel_id uuid,p_limit integer default 80)
returns table(message_id uuid,channel_id uuid,sender_id uuid,sender_name text,sender_role text,body text,reply_to_id uuid,metadata jsonb,created_at timestamptz,mine boolean)
language plpgsql stable security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 if not exists(select 1 from public.school_chat_channels c where c.id=p_channel_id and c.active=true) then raise exception 'channel_not_found' using errcode='P0002'; end if;
 return query
 select x.id,x.channel_id,x.sender_id,coalesce(p.full_name,'Equipe Live Connect'),p.role::text,x.body,x.reply_to_id,x.metadata,x.created_at,(x.sender_id=auth.uid())
 from (
   select m.* from public.school_chat_messages m
   where m.channel_id=p_channel_id and m.deleted_at is null
   order by m.created_at desc limit greatest(1,least(coalesce(p_limit,80),200))
 ) x
 left join public.profiles p on p.id=x.sender_id
 order by x.created_at asc;
end $$;

create or replace function public.school_chat_send(p_channel_id uuid,p_body text,p_reply_to_id uuid default null)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_id uuid;v_body text:=trim(coalesce(p_body,''));
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 if char_length(v_body)<1 or char_length(v_body)>2500 then raise exception 'invalid_message' using errcode='22023'; end if;
 if not exists(select 1 from public.school_chat_channels c where c.id=p_channel_id and c.active=true) then raise exception 'channel_not_found' using errcode='P0002'; end if;
 if p_reply_to_id is not null and not exists(select 1 from public.school_chat_messages m where m.id=p_reply_to_id and m.channel_id=p_channel_id and m.deleted_at is null) then raise exception 'invalid_reply' using errcode='22023'; end if;
 insert into public.school_chat_messages(channel_id,sender_id,body,reply_to_id) values(p_channel_id,auth.uid(),v_body,p_reply_to_id) returning id into v_id;
 insert into public.school_chat_reads(channel_id,user_id,last_read_at) values(p_channel_id,auth.uid(),now())
 on conflict(channel_id,user_id) do update set last_read_at=excluded.last_read_at;
 return jsonb_build_object('ok',true,'message_id',v_id);
end $$;

create or replace function public.school_chat_mark_read(p_channel_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 insert into public.school_chat_reads(channel_id,user_id,last_read_at) values(p_channel_id,auth.uid(),now())
 on conflict(channel_id,user_id) do update set last_read_at=excluded.last_read_at;
end $$;

create table if not exists public.commercial_chat_sessions (
 id uuid primary key default gen_random_uuid(),
 public_token uuid not null unique default gen_random_uuid(),
 lead_id uuid references public.leads(id) on delete set null,
 status text not null default 'qualifying' check (status in ('qualifying','qualified','closing','handoff','won','lost','closed')),
 stage text not null default 'name',
 full_name text,
 whatsapp text,
 age integer,
 objective text,
 course_interest text,
 course_type text,
 lead_score integer not null default 0 check (lead_score between 0 and 100),
 assigned_to uuid references auth.users(id) on delete set null,
 source text not null default 'portal_chatbot',
 utm_source text,utm_medium text,utm_campaign text,utm_content text,
 landing_page text,referrer text,
 metadata jsonb not null default '{}'::jsonb,
 last_message_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.commercial_chat_messages (
 id uuid primary key default gen_random_uuid(),
 session_id uuid not null references public.commercial_chat_sessions(id) on delete cascade,
 sender_type text not null check (sender_type in ('visitor','assistant','staff','system')),
 sender_id uuid references auth.users(id) on delete set null,
 body text not null check (char_length(body) between 1 and 4000),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table if not exists public.commercial_chat_reads (
 session_id uuid not null references public.commercial_chat_sessions(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 last_read_at timestamptz not null default now(),
 primary key(session_id,user_id)
);
create index if not exists commercial_chat_sessions_status_updated_idx on public.commercial_chat_sessions(status,updated_at desc);
create index if not exists commercial_chat_messages_session_created_idx on public.commercial_chat_messages(session_id,created_at);
alter table public.commercial_chat_sessions enable row level security;
alter table public.commercial_chat_messages enable row level security;
alter table public.commercial_chat_reads enable row level security;
revoke all on public.commercial_chat_sessions,public.commercial_chat_messages,public.commercial_chat_reads from anon,authenticated;
grant all on public.commercial_chat_sessions,public.commercial_chat_messages,public.commercial_chat_reads to service_role;

create or replace function public.school_commercial_chat_summary()
returns jsonb language plpgsql stable security definer set search_path='pg_catalog','public' as $$
declare v jsonb;
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 select jsonb_build_object(
   'open',count(*) filter(where status in ('qualifying','qualified','closing','handoff')),
   'handoff',count(*) filter(where status='handoff'),
   'closing',count(*) filter(where status='closing'),
   'won_today',count(*) filter(where status='won' and updated_at::date=current_date),
   'high_score',count(*) filter(where lead_score>=75 and status in ('qualified','closing','handoff'))
 ) into v from public.commercial_chat_sessions;
 return coalesce(v,'{}'::jsonb);
end $$;

create or replace function public.school_commercial_chat_sessions(p_limit integer default 120,p_status text default null)
returns table(session_id uuid,lead_id uuid,status text,stage text,full_name text,whatsapp text,age integer,objective text,course_interest text,course_type text,lead_score integer,assigned_to uuid,assigned_name text,last_message text,last_message_at timestamptz,unread_count bigint,created_at timestamptz)
language plpgsql stable security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 return query
 select s.id,s.lead_id,s.status,s.stage,s.full_name,s.whatsapp,s.age,s.objective,s.course_interest,s.course_type,s.lead_score,s.assigned_to,p.full_name,lm.body,s.last_message_at,
   count(m.id) filter(where m.sender_type='visitor' and m.created_at>coalesce(r.last_read_at,'epoch'::timestamptz))::bigint,s.created_at
 from public.commercial_chat_sessions s
 left join public.profiles p on p.id=s.assigned_to
 left join public.commercial_chat_reads r on r.session_id=s.id and r.user_id=auth.uid()
 left join public.commercial_chat_messages m on m.session_id=s.id
 left join lateral (select cm.body from public.commercial_chat_messages cm where cm.session_id=s.id order by cm.created_at desc limit 1) lm on true
 where (p_status is null or p_status='' or s.status=p_status)
 group by s.id,p.full_name,lm.body,r.last_read_at
 order by s.last_message_at desc
 limit greatest(1,least(coalesce(p_limit,120),300));
end $$;

create or replace function public.school_commercial_chat_messages(p_session_id uuid,p_limit integer default 160)
returns table(message_id uuid,sender_type text,sender_id uuid,sender_name text,body text,metadata jsonb,created_at timestamptz)
language plpgsql stable security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 return query
 select x.id,x.sender_type,x.sender_id,
   case when x.sender_type='visitor' then 'Lead' when x.sender_type='assistant' then 'Assistente Live Connect' else coalesce(p.full_name,'Equipe Live Connect') end,
   x.body,x.metadata,x.created_at
 from (select m.* from public.commercial_chat_messages m where m.session_id=p_session_id order by m.created_at desc limit greatest(1,least(coalesce(p_limit,160),300))) x
 left join public.profiles p on p.id=x.sender_id
 order by x.created_at asc;
end $$;

create or replace function public.school_commercial_chat_takeover(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 update public.commercial_chat_sessions set assigned_to=auth.uid(),status='handoff',updated_at=now() where id=p_session_id;
 if not found then raise exception 'session_not_found' using errcode='P0002'; end if;
 return jsonb_build_object('ok',true,'assigned_to',auth.uid(),'status','handoff');
end $$;

create or replace function public.school_commercial_chat_release(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 update public.commercial_chat_sessions set assigned_to=null,status=case when lead_score>=75 then 'qualified' else 'qualifying' end,updated_at=now() where id=p_session_id;
 if not found then raise exception 'session_not_found' using errcode='P0002'; end if;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.school_commercial_chat_send(p_session_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_id uuid;v_body text:=trim(coalesce(p_body,''));
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 if char_length(v_body)<1 or char_length(v_body)>4000 then raise exception 'invalid_message' using errcode='22023'; end if;
 update public.commercial_chat_sessions set assigned_to=auth.uid(),status='handoff',last_message_at=now(),updated_at=now() where id=p_session_id;
 if not found then raise exception 'session_not_found' using errcode='P0002'; end if;
 insert into public.commercial_chat_messages(session_id,sender_type,sender_id,body) values(p_session_id,'staff',auth.uid(),v_body) returning id into v_id;
 return jsonb_build_object('ok',true,'message_id',v_id);
end $$;

create or replace function public.school_commercial_chat_mark_read(p_session_id uuid)
returns void language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 insert into public.commercial_chat_reads(session_id,user_id,last_read_at) values(p_session_id,auth.uid(),now())
 on conflict(session_id,user_id) do update set last_read_at=excluded.last_read_at;
end $$;

create or replace function public.school_commercial_chat_set_status(p_session_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='pg_catalog','public' as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_status not in ('qualifying','qualified','closing','handoff','won','lost','closed') then raise exception 'invalid_status' using errcode='22023'; end if;
 update public.commercial_chat_sessions set status=p_status,updated_at=now() where id=p_session_id;
 if not found then raise exception 'session_not_found' using errcode='P0002'; end if;
 return jsonb_build_object('ok',true,'status',p_status);
end $$;

revoke all on function public.school_chat_channels() from public,anon;
revoke all on function public.school_chat_messages(uuid,integer) from public,anon;
revoke all on function public.school_chat_send(uuid,text,uuid) from public,anon;
revoke all on function public.school_chat_mark_read(uuid) from public,anon;
revoke all on function public.school_commercial_chat_summary() from public,anon;
revoke all on function public.school_commercial_chat_sessions(integer,text) from public,anon;
revoke all on function public.school_commercial_chat_messages(uuid,integer) from public,anon;
revoke all on function public.school_commercial_chat_takeover(uuid) from public,anon;
revoke all on function public.school_commercial_chat_release(uuid) from public,anon;
revoke all on function public.school_commercial_chat_send(uuid,text) from public,anon;
revoke all on function public.school_commercial_chat_mark_read(uuid) from public,anon;
revoke all on function public.school_commercial_chat_set_status(uuid,text) from public,anon;
grant execute on function public.school_chat_channels() to authenticated;
grant execute on function public.school_chat_messages(uuid,integer) to authenticated;
grant execute on function public.school_chat_send(uuid,text,uuid) to authenticated;
grant execute on function public.school_chat_mark_read(uuid) to authenticated;
grant execute on function public.school_commercial_chat_summary() to authenticated;
grant execute on function public.school_commercial_chat_sessions(integer,text) to authenticated;
grant execute on function public.school_commercial_chat_messages(uuid,integer) to authenticated;
grant execute on function public.school_commercial_chat_takeover(uuid) to authenticated;
grant execute on function public.school_commercial_chat_release(uuid) to authenticated;
grant execute on function public.school_commercial_chat_send(uuid,text) to authenticated;
grant execute on function public.school_commercial_chat_mark_read(uuid) to authenticated;
grant execute on function public.school_commercial_chat_set_status(uuid,text) to authenticated;
