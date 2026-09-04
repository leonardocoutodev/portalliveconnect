-- Live Connect V5.9.0 — lifecycle do Lico, memória/aprendizado e chat privado por departamentos

alter table public.school_chat_channels
  add column if not exists channel_type text not null default 'public',
  add column if not exists participant_roles text[] not null default '{}'::text[];

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_chat_channels'::regclass
      and conname='school_chat_channels_type_check'
  ) then
    alter table public.school_chat_channels
      add constraint school_chat_channels_type_check
      check (channel_type in ('public','private'));
  end if;
end $$;

insert into public.school_chat_channels(slug,name,description,active,sort_order,channel_type,participant_roles)
values
 ('priv-comercial-secretaria','Comercial ↔ Secretaria','Conversa privada entre Comercial e Secretaria.',true,110,'private',array['admin_comercial','secretaria']),
 ('priv-comercial-diretoria','Comercial ↔ Diretoria','Conversa privada entre Comercial e Diretoria.',true,120,'private',array['admin_comercial','diretoria']),
 ('priv-secretaria-diretoria','Secretaria ↔ Diretoria','Conversa privada entre Secretaria e Diretoria.',true,130,'private',array['secretaria','diretoria'])
on conflict (slug) do update set
 name=excluded.name,description=excluded.description,active=true,sort_order=excluded.sort_order,
 channel_type=excluded.channel_type,participant_roles=excluded.participant_roles,updated_at=now();

create or replace function public.school_chat_channels()
returns table(channel_id uuid,slug text,name text,description text,unread_count bigint,last_message text,last_message_at timestamptz)
language plpgsql stable security definer
set search_path='pg_catalog','public','private'
as $$
declare v_role text; v_owner boolean;
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 select p.role::text into v_role from public.profiles p where p.id=auth.uid();
 select exists(select 1 from private.system_owner o where o.user_id=auth.uid()) into v_owner;
 return query
 select c.id,c.slug,c.name,c.description,
   count(m.id) filter(where m.created_at>coalesce(r.last_read_at,'epoch'::timestamptz) and m.sender_id<>auth.uid())::bigint,
   lm.body,lm.created_at
 from public.school_chat_channels c
 left join public.school_chat_reads r on r.channel_id=c.id and r.user_id=auth.uid()
 left join public.school_chat_messages m on m.channel_id=c.id and m.deleted_at is null
 left join lateral (
   select mm.body,mm.created_at from public.school_chat_messages mm
   where mm.channel_id=c.id and mm.deleted_at is null
   order by mm.created_at desc limit 1
 ) lm on true
 where c.active=true and (c.channel_type='public' or v_owner or v_role=any(c.participant_roles))
 group by c.id,c.slug,c.name,c.description,c.sort_order,r.last_read_at,lm.body,lm.created_at
 order by c.sort_order,c.name;
end $$;

create or replace function public.school_chat_messages(p_channel_id uuid,p_limit integer default 80)
returns table(message_id uuid,channel_id uuid,sender_id uuid,sender_name text,sender_role text,body text,reply_to_id uuid,metadata jsonb,created_at timestamptz,mine boolean)
language plpgsql stable security definer
set search_path='pg_catalog','public','private'
as $$
declare v_role text; v_owner boolean;
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 select p.role::text into v_role from public.profiles p where p.id=auth.uid();
 select exists(select 1 from private.system_owner o where o.user_id=auth.uid()) into v_owner;
 if not exists(
   select 1 from public.school_chat_channels c
   where c.id=p_channel_id and c.active=true
     and (c.channel_type='public' or v_owner or v_role=any(c.participant_roles))
 ) then raise exception 'channel_not_found' using errcode='P0002'; end if;
 return query
 select x.id,x.channel_id,x.sender_id,coalesce(p.full_name,'Equipe Live Connect'),
   case when exists(select 1 from private.system_owner o where o.user_id=x.sender_id)
        then 'admin_comercial' else p.role::text end,
   x.body,x.reply_to_id,x.metadata,x.created_at,(x.sender_id=auth.uid())
 from (
   select m.* from public.school_chat_messages m
   where m.channel_id=p_channel_id and m.deleted_at is null
   order by m.created_at desc limit greatest(1,least(coalesce(p_limit,80),200))
 ) x
 left join public.profiles p on p.id=x.sender_id
 order by x.created_at asc;
end $$;

create or replace function public.school_chat_send(p_channel_id uuid,p_body text,p_reply_to_id uuid default null)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v_id uuid;v_body text:=trim(coalesce(p_body,''));v_role text;v_owner boolean;v_can_write boolean;
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 if char_length(v_body)<1 or char_length(v_body)>2500 then raise exception 'invalid_message' using errcode='22023'; end if;
 select p.role::text into v_role from public.profiles p where p.id=auth.uid();
 select exists(select 1 from private.system_owner o where o.user_id=auth.uid()) into v_owner;
 select exists(
   select 1 from public.school_chat_channels c
   where c.id=p_channel_id and c.active=true
     and (
       c.channel_type='public'
       or (v_owner and 'admin_comercial'=any(c.participant_roles))
       or (not v_owner and v_role=any(c.participant_roles))
     )
 ) into v_can_write;
 if not v_can_write then raise exception 'channel_not_found' using errcode='P0002'; end if;
 if p_reply_to_id is not null and not exists(
   select 1 from public.school_chat_messages m
   where m.id=p_reply_to_id and m.channel_id=p_channel_id and m.deleted_at is null
 ) then raise exception 'invalid_reply' using errcode='22023'; end if;
 insert into public.school_chat_messages(channel_id,sender_id,body,reply_to_id)
 values(p_channel_id,auth.uid(),v_body,p_reply_to_id) returning id into v_id;
 insert into public.school_chat_reads(channel_id,user_id,last_read_at)
 values(p_channel_id,auth.uid(),now())
 on conflict(channel_id,user_id) do update set last_read_at=excluded.last_read_at;
 return jsonb_build_object('ok',true,'message_id',v_id);
end $$;

create or replace function public.school_chat_mark_read(p_channel_id uuid)
returns void language plpgsql security definer
set search_path='pg_catalog','public','private'
as $$
declare v_role text;v_owner boolean;
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 select p.role::text into v_role from public.profiles p where p.id=auth.uid();
 select exists(select 1 from private.system_owner o where o.user_id=auth.uid()) into v_owner;
 if not exists(
   select 1 from public.school_chat_channels c
   where c.id=p_channel_id and c.active=true
     and (c.channel_type='public' or v_owner or v_role=any(c.participant_roles))
 ) then raise exception 'channel_not_found' using errcode='P0002'; end if;
 insert into public.school_chat_reads(channel_id,user_id,last_read_at)
 values(p_channel_id,auth.uid(),now())
 on conflict(channel_id,user_id) do update set last_read_at=excluded.last_read_at;
end $$;

create table if not exists public.commercial_chat_memories(
 id uuid primary key default gen_random_uuid(),
 visitor_key uuid not null unique,
 lead_id uuid references public.leads(id) on delete set null,
 memory jsonb not null default '{}'::jsonb,
 conversation_count integer not null default 0,
 last_seen_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

alter table public.commercial_chat_sessions
 add column if not exists visitor_key uuid,
 add column if not exists memory_id uuid references public.commercial_chat_memories(id) on delete set null,
 add column if not exists expires_at timestamptz,
 add column if not exists ended_at timestamptz,
 add column if not exists end_reason text,
 add column if not exists restarted_from uuid references public.commercial_chat_sessions(id) on delete set null;

create index if not exists commercial_chat_sessions_visitor_key_idx
 on public.commercial_chat_sessions(visitor_key,last_message_at desc);
create index if not exists commercial_chat_sessions_expiry_idx
 on public.commercial_chat_sessions(expires_at) where ended_at is null;

create table if not exists public.lico_runtime_settings(
 id smallint primary key check(id=1),
 session_idle_minutes integer not null default 30 check(session_idle_minutes between 5 and 240),
 memory_enabled boolean not null default true,
 learning_enabled boolean not null default true,
 updated_at timestamptz not null default now()
);
insert into public.lico_runtime_settings(id,session_idle_minutes,memory_enabled,learning_enabled)
values(1,30,true,true) on conflict(id) do nothing;

create table if not exists public.lico_learning_events(
 id uuid primary key default gen_random_uuid(),
 session_id uuid references public.commercial_chat_sessions(id) on delete set null,
 lead_id uuid references public.leads(id) on delete set null,
 event_type text not null,
 topic text,
 course_id uuid references public.courses(id) on delete set null,
 course_name text,
 context jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists lico_learning_events_type_created_idx
 on public.lico_learning_events(event_type,created_at desc);

create table if not exists public.lico_course_learning_stats(
 course_id uuid primary key references public.courses(id) on delete cascade,
 selections integer not null default 0,
 wins integer not null default 0,
 losses integer not null default 0,
 handoffs integer not null default 0,
 updated_at timestamptz not null default now()
);

alter table public.commercial_chat_memories enable row level security;
alter table public.lico_runtime_settings enable row level security;
alter table public.lico_learning_events enable row level security;
alter table public.lico_course_learning_stats enable row level security;
revoke all on public.commercial_chat_memories,public.lico_runtime_settings,public.lico_learning_events,public.lico_course_learning_stats from anon,authenticated;
grant all on public.commercial_chat_memories,public.lico_runtime_settings,public.lico_learning_events,public.lico_course_learning_stats to service_role;

update public.commercial_chat_sessions
set expires_at=coalesce(expires_at,last_message_at+interval '30 minutes')
where ended_at is null;

create or replace function public.school_commercial_chat_sessions(p_limit integer default 120,p_status text default null)
returns table(
 session_id uuid,lead_id uuid,status text,stage text,full_name text,whatsapp text,age integer,
 student_name text,student_age integer,relationship text,guardian_required boolean,guardian_is_contact boolean,guardian_name text,guardian_whatsapp text,
 studies boolean,school_level text,study_shift text,works boolean,ever_worked boolean,current_occupation text,work_schedule text,
 availability text,availability_period text,night_slot_confirmed boolean,objective text,start_timeline text,decision_factor text,decision_authority boolean,email text,
 preferred_class_id uuid,preferred_schedule text,course_interest text,course_type text,lead_score integer,assigned_to uuid,assigned_name text,
 qualification_completed_at timestamptz,last_message text,last_message_at timestamptz,unread_count bigint,created_at timestamptz
)
language plpgsql volatile security definer
set search_path='pg_catalog','public'
as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 update public.commercial_chat_sessions s
 set status='closed',ended_at=coalesce(s.ended_at,now()),end_reason=coalesce(s.end_reason,'idle_timeout'),updated_at=now()
 where s.ended_at is null and s.status not in ('won','lost','closed')
   and coalesce(s.expires_at,s.last_message_at+interval '30 minutes')<=now();
 return query
 select s.id,s.lead_id,s.status,s.stage,s.full_name,s.whatsapp,s.age,
   s.student_name,s.student_age,s.relationship,s.guardian_required,s.guardian_is_contact,s.guardian_name,s.guardian_whatsapp,
   s.studies,s.school_level,s.study_shift,s.works,s.ever_worked,s.current_occupation,s.work_schedule,
   s.availability,s.availability_period,s.night_slot_confirmed,s.objective,s.start_timeline,s.decision_factor,s.decision_authority,s.email,
   s.preferred_class_id,s.preferred_schedule,s.course_interest,s.course_type,s.lead_score,s.assigned_to,p.full_name,
   s.qualification_completed_at,lm.body,s.last_message_at,
   count(m.id) filter(where m.sender_type='visitor' and m.created_at>coalesce(r.last_read_at,'epoch'::timestamptz))::bigint,s.created_at
 from public.commercial_chat_sessions s
 left join public.profiles p on p.id=s.assigned_to
 left join public.commercial_chat_reads r on r.session_id=s.id and r.user_id=auth.uid()
 left join public.commercial_chat_messages m on m.session_id=s.id
 left join lateral(
   select cm.body from public.commercial_chat_messages cm where cm.session_id=s.id order by cm.created_at desc limit 1
 )lm on true
 where (p_status is null or p_status='' or s.status=p_status)
 group by s.id,p.full_name,lm.body,r.last_read_at
 order by s.last_message_at desc
 limit greatest(1,least(coalesce(p_limit,120),300));
end $$;

revoke all on function public.school_chat_channels() from public,anon;
revoke all on function public.school_chat_messages(uuid,integer) from public,anon;
revoke all on function public.school_chat_send(uuid,text,uuid) from public,anon;
revoke all on function public.school_chat_mark_read(uuid) from public,anon;
grant execute on function public.school_chat_channels() to authenticated;
grant execute on function public.school_chat_messages(uuid,integer) to authenticated;
grant execute on function public.school_chat_send(uuid,text,uuid) to authenticated;
grant execute on function public.school_chat_mark_read(uuid) to authenticated;
