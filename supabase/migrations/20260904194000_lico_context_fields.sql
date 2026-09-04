alter table public.commercial_chat_sessions add column if not exists school_level text;
alter table public.commercial_chat_sessions add column if not exists ever_worked boolean;
alter table public.commercial_chat_sessions add column if not exists current_occupation text;
alter table public.commercial_chat_sessions add column if not exists preferred_class_id uuid references public.classes(id) on delete set null;
alter table public.commercial_chat_sessions add column if not exists preferred_schedule text;

create or replace function public.school_chat_messages(p_channel_id uuid,p_limit integer default 80)
returns table(
  message_id uuid,channel_id uuid,sender_id uuid,sender_name text,sender_role text,
  body text,reply_to_id uuid,metadata jsonb,created_at timestamptz,mine boolean
)
language plpgsql stable security definer
set search_path='pg_catalog','public','private'
as $$
begin
 if not public.is_staff() then raise exception 'forbidden' using errcode='42501'; end if;
 if not exists(select 1 from public.school_chat_channels c where c.id=p_channel_id and c.active=true) then
   raise exception 'channel_not_found' using errcode='P0002';
 end if;
 return query
 select
   x.id,x.channel_id,x.sender_id,
   case when exists(select 1 from private.system_owner o where o.user_id=x.sender_id) then 'Comercial'
        else coalesce(p.full_name,'Equipe Live Connect') end,
   case when exists(select 1 from private.system_owner o where o.user_id=x.sender_id) then 'admin_comercial'
        else p.role::text end,
   x.body,x.reply_to_id,x.metadata,x.created_at,(x.sender_id=auth.uid())
 from (
   select m.* from public.school_chat_messages m
   where m.channel_id=p_channel_id and m.deleted_at is null
   order by m.created_at desc
   limit greatest(1,least(coalesce(p_limit,80),200))
 ) x
 left join public.profiles p on p.id=x.sender_id
 order by x.created_at asc;
end $$;

drop function if exists public.school_commercial_chat_sessions(integer,text);
create function public.school_commercial_chat_sessions(p_limit integer default 120,p_status text default null)
returns table(
 session_id uuid,lead_id uuid,status text,stage text,full_name text,whatsapp text,age integer,
 student_name text,student_age integer,relationship text,studies boolean,school_level text,study_shift text,
 works boolean,ever_worked boolean,current_occupation text,work_schedule text,availability text,availability_period text,
 night_slot_confirmed boolean,objective text,start_timeline text,decision_factor text,decision_authority boolean,email text,
 course_interest text,course_type text,preferred_class_id uuid,preferred_schedule text,
 lead_score integer,assigned_to uuid,assigned_name text,qualification_completed_at timestamptz,
 last_message text,last_message_at timestamptz,unread_count bigint,created_at timestamptz
)
language plpgsql stable security definer
set search_path='pg_catalog','public'
as $$
begin
 if not public.is_admin_comercial() then raise exception 'forbidden' using errcode='42501'; end if;
 return query
 select
   s.id,s.lead_id,s.status,s.stage,s.full_name,s.whatsapp,s.age,
   s.student_name,s.student_age,s.relationship,s.studies,s.school_level,s.study_shift,
   s.works,s.ever_worked,s.current_occupation,s.work_schedule,s.availability,s.availability_period,
   s.night_slot_confirmed,s.objective,s.start_timeline,s.decision_factor,s.decision_authority,s.email,
   s.course_interest,s.course_type,s.preferred_class_id,s.preferred_schedule,
   s.lead_score,s.assigned_to,p.full_name,s.qualification_completed_at,lm.body,s.last_message_at,
   count(m.id) filter(where m.sender_type='visitor' and m.created_at>coalesce(r.last_read_at,'epoch'::timestamptz))::bigint,
   s.created_at
 from public.commercial_chat_sessions s
 left join public.profiles p on p.id=s.assigned_to
 left join public.commercial_chat_reads r on r.session_id=s.id and r.user_id=auth.uid()
 left join public.commercial_chat_messages m on m.session_id=s.id
 left join lateral (
   select cm.body from public.commercial_chat_messages cm
   where cm.session_id=s.id order by cm.created_at desc limit 1
 ) lm on true
 where (p_status is null or p_status='' or s.status=p_status)
 group by s.id,p.full_name,lm.body,r.last_read_at
 order by s.last_message_at desc
 limit greatest(1,least(coalesce(p_limit,120),300));
end $$;

revoke all on function public.school_chat_messages(uuid,integer) from public,anon;
revoke all on function public.school_commercial_chat_sessions(integer,text) from public,anon;
grant execute on function public.school_chat_messages(uuid,integer) to authenticated;
grant execute on function public.school_commercial_chat_sessions(integer,text) to authenticated;