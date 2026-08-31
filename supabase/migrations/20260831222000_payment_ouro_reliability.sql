-- Payment + Ouro automatic enrollment reliability fixes
-- 2026-08-31

alter table public.payments
  drop constraint if exists payments_kind_check;

alter table public.payments
  add constraint payments_kind_check
  check (kind = any (array[
    'matricula'::text,
    'primeira_mensalidade'::text,
    'profissao_rapida_total'::text
  ]));

alter table public.payment_checkout_sessions
  drop constraint if exists payment_checkout_sessions_scope_check;

alter table public.payment_checkout_sessions
  add constraint payment_checkout_sessions_scope_check
  check (scope = any (array[
    'initial'::text,
    'enrollment'::text,
    'first_monthly'::text,
    'profissao_rapida'::text
  ]));

CREATE OR REPLACE FUNCTION private.portal_retry_automatic_enrollments(p_limit integer DEFAULT 10)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  r record;
  v_count integer := 0;
  v_result jsonb;
begin
  update public.portal_enrollment_queue q
     set status='pendencia_documental',
         ouro_last_error='email_required_for_ouro_auto',
         ouro_last_response=jsonb_build_object('stage','retry_precheck','reason','email_required'),
         updated_at=now()
    from public.leads l
   where q.lead_id=l.id
     and q.status in ('paga_aguardando_matricula','em_cadastro_ouro')
     and lower(trim(coalesce(l.email,''))) !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$';

  for r in
    select q.id
    from public.portal_enrollment_queue q
    join public.leads l on l.id=q.lead_id
    where q.status in ('paga_aguardando_matricula','em_cadastro_ouro')
      and lower(trim(coalesce(l.email,''))) ~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
      and q.ouro_attempt_count < 6
      and (
        q.ouro_last_attempt_at is null
        or q.ouro_last_attempt_at < now()-interval '5 minutes'
      )
    order by q.updated_at
    limit greatest(1,least(coalesce(p_limit,10),50))
    for update of q skip locked
  loop
    v_result := private.portal_auto_process_paid_enrollment(r.id);
    v_count := v_count+1;
  end loop;

  return v_count;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.portal_mp_bridge_create(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public'
AS $function$
declare
  v_resp extensions.http_response;
  v_body jsonb;
  v_session public.payment_checkout_sessions%rowtype;
  v_init text;
begin
  select * into v_session
  from public.payment_checkout_sessions
  where public_token=p_token
    and status in ('created','pending')
    and (expires_at is null or expires_at>now())
  for update;

  if not found then
    return jsonb_build_object('ok',false,'error','checkout_not_found');
  end if;

  if v_session.status='pending' and coalesce(v_session.init_point,'')<>'' then
    return jsonb_build_object(
      'ok',true,
      'reused',true,
      'id',v_session.provider_preference_id,
      'init_point',v_session.init_point,
      'sandbox_init_point',v_session.sandbox_init_point,
      'http_status',200
    );
  end if;

  v_resp := extensions.http((
    'POST'::extensions.http_method,
    'https://kvwsqfnyebyjncfgvqnd.supabase.co/functions/v1/liveconnect-mercadopago-bridge'::varchar,
    array[extensions.http_header('Content-Type','application/json')],
    'application/json'::varchar,
    jsonb_build_object('action','create','token',p_token::text)::text::varchar
  )::extensions.http_request);

  begin
    v_body := coalesce(v_resp.content,'{}')::jsonb;
  exception when others then
    v_body := jsonb_build_object('ok',false,'error','bridge_non_json');
  end;

  if v_resp.status <> 200 or not coalesce((v_body->>'ok')::boolean,false) then
    update public.payment_checkout_sessions
       set status='error',
           metadata=coalesce(metadata,'{}'::jsonb)
                    || jsonb_build_object('provider_error',v_body,'provider_http_status',v_resp.status),
           updated_at=now()
     where id=v_session.id;

    return jsonb_build_object(
      'ok',false,
      'error',coalesce(v_body->>'error','bridge_http_error'),
      'message',v_body->>'message',
      'http_status',v_resp.status
    );
  end if;

  v_init := coalesce(v_body->>'init_point',v_body->>'sandbox_init_point');

  update public.payment_checkout_sessions
     set status='pending',
         provider_preference_id=nullif(v_body->>'id',''),
         init_point=v_init,
         sandbox_init_point=nullif(v_body->>'sandbox_init_point',''),
         updated_at=now()
   where id=v_session.id;

  return v_body
         || jsonb_build_object(
              'http_status',v_resp.status,
              'session_id',v_session.id,
              'token',v_session.public_token
            );
end
$function$
;

CREATE OR REPLACE FUNCTION public.portal_mp_bridge_payment(p_payment_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'extensions', 'public'
AS $function$
declare
  v_resp extensions.http_response;
  v_body jsonb;
begin
  if p_payment_id !~ '^[0-9]+$' then
    return jsonb_build_object('ok',false,'error','invalid_payment_id');
  end if;

  v_resp := extensions.http((
    'POST'::extensions.http_method,
    'https://kvwsqfnyebyjncfgvqnd.supabase.co/functions/v1/liveconnect-mercadopago-bridge'::varchar,
    array[extensions.http_header('Content-Type','application/json')],
    'application/json'::varchar,
    jsonb_build_object('action','payment','payment_id',p_payment_id)::text::varchar
  )::extensions.http_request);

  begin
    v_body := coalesce(v_resp.content,'{}')::jsonb;
  exception when others then
    v_body := jsonb_build_object('ok',false,'error','bridge_non_json');
  end;

  if v_resp.status <> 200 then
    return jsonb_build_object(
      'ok',false,
      'error',coalesce(v_body->>'error','bridge_http_error'),
      'http_status',v_resp.status
    );
  end if;

  return v_body || jsonb_build_object('http_status',v_resp.status);
end
$function$
;

CREATE OR REPLACE FUNCTION public.sync_portal_enrollment_queue_payment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_lead uuid;
  v_course uuid;
  v_mode text;
  v_queue_id uuid;
  v_email text;
begin
  select e.lead_id,e.course_id,e.commercial_mode
    into v_lead,v_course,v_mode
  from public.enrollments e
  where e.id=new.enrollment_id;

  if v_lead is null then
    return new;
  end if;

  select lower(trim(coalesce(l.email,'')))
    into v_email
  from public.leads l
  where l.id=v_lead;

  if (
    ((v_mode='profissao_rapida' and new.kind='profissao_rapida_total')
      or (v_mode<>'profissao_rapida' and new.kind='matricula'))
    and (new.status::text='pago' or lower(coalesce(new.provider_status,'')) in ('approved','paid'))
  ) or (
    v_mode<>'profissao_rapida'
    and new.kind='matricula'
    and new.status::text='isento'
  ) then

    if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
      update public.portal_enrollment_queue q
         set status='pendencia_documental',
             payment_approved_at=coalesce(q.payment_approved_at,now()),
             ouro_last_error='email_required_for_ouro_auto',
             ouro_last_response=jsonb_build_object(
               'stage','precheck',
               'reason','email_required'
             ),
             updated_at=now()
       where q.lead_id=v_lead
         and (q.course_id is null or q.course_id=v_course)
         and q.status not in ('matriculada_ouro','matriculada_manual','cancelada');

      return new;
    end if;

    for v_queue_id in
      update public.portal_enrollment_queue q
         set status='paga_aguardando_matricula',
             payment_approved_at=coalesce(q.payment_approved_at,now()),
             ouro_last_error=null,
             updated_at=now()
       where q.lead_id=v_lead
         and (q.course_id is null or q.course_id=v_course)
         and q.status not in ('matriculada_ouro','matriculada_manual','cancelada')
      returning q.id
    loop
      begin
        perform private.portal_auto_process_paid_enrollment(v_queue_id);
      exception when others then
        update public.portal_enrollment_queue
           set ouro_last_error=left(sqlerrm,500),
               updated_at=now()
         where id=v_queue_id;
      end;
    end loop;

  elsif (
    ((v_mode='profissao_rapida' and new.kind='profissao_rapida_total')
      or (v_mode<>'profissao_rapida' and new.kind='matricula'))
    and new.status::text='pendente'
  ) then
    update public.portal_enrollment_queue q
       set status=case when q.status='nova' then 'aguardando_pagamento' else q.status end,
           updated_at=now()
     where q.lead_id=v_lead
       and (q.course_id is null or q.course_id=v_course)
       and q.status not in (
         'matriculada_ouro','matriculada_manual','cancelada',
         'paga_aguardando_matricula','em_cadastro_ouro'
       );
  end if;

  return new;
end
$function$
;


revoke all on function public.portal_mp_bridge_create(uuid) from public,anon,authenticated;
revoke all on function public.portal_mp_bridge_payment(text) from public,anon,authenticated;
grant execute on function public.portal_mp_bridge_create(uuid) to service_role;
grant execute on function public.portal_mp_bridge_payment(text) to service_role;
