alter table public.school_chat_tasks
  add column if not exists priority text not null default 'normal',
  add column if not exists remind_before_minutes integer not null default 60,
  add column if not exists repeat_minutes integer not null default 60,
  add column if not exists next_reminder_at timestamptz,
  add column if not exists last_reminded_at timestamptz,
  add column if not exists reminder_count integer not null default 0,
  add column if not exists completion_note text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_chat_tasks'::regclass
      and conname='school_chat_tasks_priority_check'
  ) then
    alter table public.school_chat_tasks
      add constraint school_chat_tasks_priority_check
      check (priority in ('normal','alta','urgente'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_chat_tasks'::regclass
      and conname='school_chat_tasks_remind_before_check'
  ) then
    alter table public.school_chat_tasks
      add constraint school_chat_tasks_remind_before_check
      check (remind_before_minutes between 0 and 10080);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_chat_tasks'::regclass
      and conname='school_chat_tasks_repeat_check'
  ) then
    alter table public.school_chat_tasks
      add constraint school_chat_tasks_repeat_check
      check (repeat_minutes between 15 and 10080);
  end if;
end $$;

create index if not exists school_chat_tasks_assignee_pending_due_idx
  on public.school_chat_tasks(assigned_to,status,due_at)
  where status='pendente';

create index if not exists school_chat_tasks_next_reminder_idx
  on public.school_chat_tasks(next_reminder_at)
  where status='pendente' and next_reminder_at is not null;

create or replace function public.school_chat_conversations_v2()
returns table(
  channel_id uuid,
  slug text,
  unread_count bigint,
  last_message text,
  last_message_at timestamptz,
  kind text,
  can_write boolean,
  counterpart_id uuid,
  counterpart_name text,
  counterpart_department text,
  counterpart_presence text,
  participant_a_name text,
  participant_a_department text,
  participant_b_name text,
  participant_b_department text
)
language sql
stable
security invoker
set search_path to 'pg_catalog','public'
as $$
  select x.*
  from public.school_chat_conversations() x
  order by x.last_message_at desc nulls last, x.channel_id;
$$;

revoke all on function public.school_chat_conversations_v2() from public,anon;
grant execute on function public.school_chat_conversations_v2() to authenticated,service_role;

create or replace function public.school_chat_task_assignees()
returns table(user_id uuid,full_name text,role text)
language sql
stable
security definer
set search_path to 'pg_catalog','public'
as $$
  select p.id,p.full_name,p.role::text
  from public.profiles p
  where public.is_staff()
    and p.active=true
    and p.role::text in ('master_admin','coadmin','diretoria','admin_comercial','secretaria','instrutora')
  order by p.full_name;
$$;

revoke all on function public.school_chat_task_assignees() from public,anon;
grant execute on function public.school_chat_task_assignees() to authenticated,service_role;

create or replace function public.school_chat_create_task_from_message_v2(
  p_message_id uuid,
  p_title text,
  p_assigned_to uuid default null,
  p_due_at timestamptz default null,
  p_remind_before_minutes integer default 60,
  p_repeat_minutes integer default 60,
  p_priority text default 'normal'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  v_channel_id uuid;
  v_body text;
  v_task_id uuid;
  v_assigned_to uuid := coalesce(p_assigned_to,auth.uid());
  v_remind integer := coalesce(p_remind_before_minutes,60);
  v_repeat integer := coalesce(p_repeat_minutes,60);
  v_priority text := lower(coalesce(nullif(trim(p_priority),''),'normal'));
  v_next timestamptz;
begin
  if not public.school_has_permission('manage_chat') then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select m.channel_id,m.body
    into v_channel_id,v_body
  from public.school_chat_messages m
  where m.id=p_message_id
    and m.deleted_at is null;

  if v_channel_id is null or not public.school_chat_can_access(v_channel_id,true) then
    raise exception 'message_not_found' using errcode='P0002';
  end if;

  if nullif(trim(coalesce(p_title,'')),'') is null then
    raise exception 'task_title_required' using errcode='22023';
  end if;

  if p_due_at is null then
    raise exception 'task_due_at_required' using errcode='22023';
  end if;

  if p_due_at <= now() then
    raise exception 'task_due_at_must_be_future' using errcode='22023';
  end if;

  if not exists(
    select 1 from public.profiles p
    where p.id=v_assigned_to and p.active=true
  ) then
    raise exception 'assignee_not_found' using errcode='P0002';
  end if;

  if v_priority not in ('normal','alta','urgente') then
    raise exception 'invalid_priority' using errcode='22023';
  end if;

  if v_remind not between 0 and 10080 then
    raise exception 'invalid_reminder' using errcode='22023';
  end if;

  if v_repeat not between 15 and 10080 then
    raise exception 'invalid_repeat' using errcode='22023';
  end if;

  v_next := greatest(now(),p_due_at-make_interval(mins=>v_remind));

  insert into public.school_chat_tasks(
    channel_id,source_message_id,title,description,assigned_to,due_at,status,created_by,
    priority,remind_before_minutes,repeat_minutes,next_reminder_at
  )
  values(
    v_channel_id,p_message_id,trim(p_title),v_body,v_assigned_to,p_due_at,'pendente',auth.uid(),
    v_priority,v_remind,v_repeat,v_next
  )
  returning id into v_task_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),'school_chat_task_created','school_chat_task',v_task_id,
    jsonb_build_object(
      'source_message_id',p_message_id,
      'assigned_to',v_assigned_to,
      'due_at',p_due_at,
      'priority',v_priority,
      'remind_before_minutes',v_remind,
      'repeat_minutes',v_repeat
    )
  );

  return jsonb_build_object(
    'ok',true,
    'task_id',v_task_id,
    'assigned_to',v_assigned_to,
    'due_at',p_due_at,
    'next_reminder_at',v_next
  );
end
$$;

revoke all on function public.school_chat_create_task_from_message_v2(uuid,text,uuid,timestamptz,integer,integer,text) from public,anon;
grant execute on function public.school_chat_create_task_from_message_v2(uuid,text,uuid,timestamptz,integer,integer,text) to authenticated,service_role;

create or replace function public.school_chat_tasks_list_v2(
  p_status text default null,
  p_limit integer default 100
)
returns table(
  task_id uuid,
  channel_id uuid,
  channel_name text,
  source_message_id uuid,
  title text,
  description text,
  assigned_to uuid,
  assigned_name text,
  due_at timestamptz,
  status text,
  priority text,
  remind_before_minutes integer,
  repeat_minutes integer,
  next_reminder_at timestamptz,
  last_reminded_at timestamptz,
  reminder_count integer,
  created_by uuid,
  created_by_name text,
  created_at timestamptz,
  completed_at timestamptz,
  completion_note text,
  is_mine boolean,
  is_overdue boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public','private'
as $$
declare
  v_owner boolean;
begin
  if not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  select public.is_owner() into v_owner;

  return query
  select
    t.id,t.channel_id,c.name,t.source_message_id,t.title,t.description,
    t.assigned_to,ap.full_name,t.due_at,t.status,t.priority,
    t.remind_before_minutes,t.repeat_minutes,t.next_reminder_at,t.last_reminded_at,t.reminder_count,
    t.created_by,cp.full_name,t.created_at,t.completed_at,t.completion_note,
    (t.assigned_to=auth.uid()),
    (t.status='pendente' and t.due_at is not null and t.due_at<now())
  from public.school_chat_tasks t
  left join public.school_chat_channels c on c.id=t.channel_id
  left join public.profiles ap on ap.id=t.assigned_to
  left join public.profiles cp on cp.id=t.created_by
  where (p_status is null or p_status='' or t.status=p_status)
    and (
      v_owner
      or t.assigned_to=auth.uid()
      or t.created_by=auth.uid()
      or (t.channel_id is not null and public.school_chat_can_access(t.channel_id,false))
    )
  order by
    (t.status='pendente') desc,
    (t.status='pendente' and t.due_at is not null and t.due_at<now()) desc,
    case t.priority when 'urgente' then 1 when 'alta' then 2 else 3 end,
    t.due_at nulls last,
    t.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),300));
end
$$;

revoke all on function public.school_chat_tasks_list_v2(text,integer) from public,anon;
grant execute on function public.school_chat_tasks_list_v2(text,integer) to authenticated,service_role;

create or replace function public.school_chat_task_obligations(p_limit integer default 30)
returns table(
  task_id uuid,
  channel_id uuid,
  channel_name text,
  source_message_id uuid,
  title text,
  description text,
  due_at timestamptz,
  priority text,
  created_by_name text,
  next_reminder_at timestamptz,
  reminder_count integer,
  is_overdue boolean
)
language plpgsql
stable
security definer
set search_path to 'pg_catalog','public'
as $$
begin
  if not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  return query
  select
    t.id,t.channel_id,c.name,t.source_message_id,t.title,t.description,t.due_at,t.priority,
    cp.full_name,t.next_reminder_at,t.reminder_count,
    (t.due_at is not null and t.due_at<now())
  from public.school_chat_tasks t
  left join public.school_chat_channels c on c.id=t.channel_id
  left join public.profiles cp on cp.id=t.created_by
  where t.status='pendente'
    and t.assigned_to=auth.uid()
  order by
    (t.due_at is not null and t.due_at<now()) desc,
    case t.priority when 'urgente' then 1 when 'alta' then 2 else 3 end,
    t.due_at nulls last,
    t.created_at desc
  limit greatest(1,least(coalesce(p_limit,30),100));
end
$$;

revoke all on function public.school_chat_task_obligations(integer) from public,anon;
grant execute on function public.school_chat_task_obligations(integer) to authenticated,service_role;

create or replace function public.school_chat_task_set_status(p_task_id uuid,p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  t public.school_chat_tasks%rowtype;
  v_owner boolean;
begin
  if p_status not in ('pendente','concluida','cancelada') then
    raise exception 'invalid_status' using errcode='22023';
  end if;

  select * into t
  from public.school_chat_tasks
  where id=p_task_id
  for update;

  if not found then
    raise exception 'task_not_found' using errcode='P0002';
  end if;

  select public.is_owner() into v_owner;

  if p_status='concluida' then
    if not (v_owner or t.assigned_to=auth.uid() or t.created_by=auth.uid()) then
      raise exception 'forbidden' using errcode='42501';
    end if;
  elsif p_status='cancelada' then
    if not (v_owner or t.created_by=auth.uid()) then
      raise exception 'task_cancel_requires_creator' using errcode='42501';
    end if;
  else
    if not (v_owner or t.created_by=auth.uid()) then
      raise exception 'task_reopen_requires_creator' using errcode='42501';
    end if;
  end if;

  update public.school_chat_tasks
  set
    status=p_status,
    completed_at=case when p_status='concluida' then now() else null end,
    next_reminder_at=case
      when p_status='pendente' and due_at is not null
        then greatest(now(),due_at-make_interval(mins=>remind_before_minutes))
      else null
    end,
    updated_at=now()
  where id=p_task_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    case p_status when 'concluida' then 'school_chat_task_completed'
                  when 'cancelada' then 'school_chat_task_cancelled'
                  else 'school_chat_task_reopened' end,
    'school_chat_task',
    p_task_id,
    jsonb_build_object('status',p_status)
  );

  return jsonb_build_object('ok',true,'status',p_status);
end
$$;

revoke all on function public.school_chat_task_set_status(uuid,text) from public,anon;
grant execute on function public.school_chat_task_set_status(uuid,text) to authenticated,service_role;

create or replace function public.school_chat_task_complete(p_task_id uuid,p_completion_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
declare
  t public.school_chat_tasks%rowtype;
  v_owner boolean;
begin
  select * into t
  from public.school_chat_tasks
  where id=p_task_id
  for update;

  if not found then
    raise exception 'task_not_found' using errcode='P0002';
  end if;

  select public.is_owner() into v_owner;
  if not (v_owner or t.assigned_to=auth.uid() or t.created_by=auth.uid()) then
    raise exception 'forbidden' using errcode='42501';
  end if;

  update public.school_chat_tasks
  set status='concluida',
      completed_at=now(),
      completion_note=nullif(trim(coalesce(p_completion_note,'')),''),
      next_reminder_at=null,
      updated_at=now()
  where id=p_task_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),'school_chat_task_completed','school_chat_task',p_task_id,
    jsonb_build_object('completion_note',nullif(trim(coalesce(p_completion_note,'')),''))
  );

  return jsonb_build_object('ok',true,'status','concluida','completed_at',now());
end
$$;

revoke all on function public.school_chat_task_complete(uuid,text) from public,anon;
grant execute on function public.school_chat_task_complete(uuid,text) to authenticated,service_role;

create or replace function public.school_task_reminder_secret_matches(p_secret text)
returns boolean
language sql
stable
security definer
set search_path to 'pg_catalog','vault','extensions'
as $$
  select exists(
    select 1
    from vault.decrypted_secrets s
    where s.name='school_task_reminder_cron_secret'
      and extensions.digest(coalesce(s.decrypted_secret,''),'sha256')
          =extensions.digest(coalesce(p_secret,''),'sha256')
  );
$$;

revoke all on function public.school_task_reminder_secret_matches(text) from public,anon,authenticated;
grant execute on function public.school_task_reminder_secret_matches(text) to service_role;

create or replace function public.school_chat_task_claim_push_reminders(p_limit integer default 100)
returns table(
  task_id uuid,
  assigned_to uuid,
  channel_id uuid,
  source_message_id uuid,
  title text,
  due_at timestamptz,
  priority text,
  reminder_count integer,
  is_overdue boolean
)
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $$
begin
  return query
  with due as (
    select t.id
    from public.school_chat_tasks t
    where t.status='pendente'
      and t.assigned_to is not null
      and t.next_reminder_at is not null
      and t.next_reminder_at<=now()
    order by t.next_reminder_at,t.due_at
    for update skip locked
    limit greatest(1,least(coalesce(p_limit,100),300))
  ),
  upd as (
    update public.school_chat_tasks t
    set
      last_reminded_at=now(),
      reminder_count=t.reminder_count+1,
      next_reminder_at=case
        when t.due_at is null then now()+make_interval(mins=>greatest(15,t.repeat_minutes))
        when t.due_at>now() then t.due_at
        else now()+make_interval(mins=>greatest(15,t.repeat_minutes))
      end,
      updated_at=now()
    from due d
    where t.id=d.id
    returning t.id,t.assigned_to,t.channel_id,t.source_message_id,t.title,t.due_at,t.priority,t.reminder_count
  )
  select
    u.id,u.assigned_to,u.channel_id,u.source_message_id,u.title,u.due_at,u.priority,u.reminder_count,
    (u.due_at is not null and u.due_at<=now())
  from upd u;
end
$$;

revoke all on function public.school_chat_task_claim_push_reminders(integer) from public,anon,authenticated;
grant execute on function public.school_chat_task_claim_push_reminders(integer) to service_role;

do $$
begin
  if not exists(select 1 from vault.decrypted_secrets where name='school_task_reminder_cron_secret') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),
      'school_task_reminder_cron_secret'
    );
  end if;
end $$;

create extension if not exists pg_net with schema extensions;

do $$
declare v_jobid bigint;
begin
  select jobid into v_jobid
  from cron.job
  where jobname='school-task-reminders-every-minute'
  limit 1;
  if v_jobid is not null then
    perform cron.unschedule(v_jobid);
  end if;
end $$;

select cron.schedule(
  'school-task-reminders-every-minute',
  '* * * * *',
  $cron$
    select net.http_post(
      url:='https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/school-task-reminders',
      headers:=jsonb_build_object(
        'Content-Type','application/json',
        'x-cron-secret',(select decrypted_secret from vault.decrypted_secrets where name='school_task_reminder_cron_secret' limit 1)
      ),
      body:='{"action":"run"}'::jsonb
    );
  $cron$
);
