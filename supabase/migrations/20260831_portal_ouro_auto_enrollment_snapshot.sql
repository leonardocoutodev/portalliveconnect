-- Portal Live Connect — snapshot operacional da integração Ouro/credenciais
-- Data: 2026-08-31
-- Este arquivo NÃO contém segredos.
-- Pré-requisitos: schema base do Portal (leads, lead_interests, enrollments, payments,
-- portal_enrollment_queue, classes, class_slots, courses, audit_logs, ouro_student_links)
-- e extensões pgcrypto/http/pg_cron/supabase_vault já existentes.

alter table public.portal_enrollment_queue
  drop constraint if exists portal_enrollment_queue_status_check;

alter table public.portal_enrollment_queue
  add constraint portal_enrollment_queue_status_check
  check (status = any(array[
    'nova'::text,
    'em_analise'::text,
    'aguardando_pagamento'::text,
    'paga_aguardando_matricula'::text,
    'pendencia_documental'::text,
    'horario_indisponivel'::text,
    'aprovada_secretaria'::text,
    'em_cadastro_ouro'::text,
    'matriculada_ouro'::text,
    'matriculada_manual'::text,
    'cancelada'::text
  ]));

alter table public.portal_enrollment_queue
  add column if not exists ouro_student_id text,
  add column if not exists ouro_course_ids text[] not null default '{}',
  add column if not exists ouro_contract_ids text[] not null default '{}',
  add column if not exists ouro_attempt_count integer not null default 0,
  add column if not exists ouro_last_attempt_at timestamptz,
  add column if not exists ouro_last_error text,
  add column if not exists ouro_last_response jsonb not null default '{}',
  add column if not exists ouro_created_student boolean not null default false;

create table if not exists private.portal_access_credentials (
  id uuid primary key default extensions.gen_random_uuid(),
  queue_id uuid not null unique references public.portal_enrollment_queue(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  ouro_student_id text not null,
  username text not null,
  password_cipher bytea,
  email text,
  whatsapp text,
  token_hash bytea,
  token_expires_at timestamptz,
  viewed_at timestamptz,
  whatsapp_prepared_at timestamptz,
  whatsapp_sent_at timestamptz,
  email_status text not null default 'not_applicable'
    check (email_status in ('pending','not_configured','queued','sent','failed','not_applicable')),
  email_sent_at timestamptz,
  email_last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table private.portal_access_credentials enable row level security;

create index if not exists portal_access_credentials_token_hash_idx
  on private.portal_access_credentials(token_hash)
  where token_hash is not null;

create index if not exists portal_access_credentials_lead_id_idx
  on private.portal_access_credentials(lead_id);

do $$
begin
  if not exists (select 1 from vault.secrets where name='portal_credentials_encryption_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'portal_credentials_encryption_key',
      'Chave de criptografia das credenciais iniciais do Portal Live Connect'
    );
  end if;
end $$;

-- A chave ouro_moderno_api_key deve existir no Vault antes da operação.

-- private.ouro_api_student_by_login(p_login text)
CREATE OR REPLACE FUNCTION private.ouro_api_student_by_login(p_login text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'private', 'extensions', 'vault'
AS $function$
declare
  v_key text;
  v_resp extensions.http_response;
  v_body jsonb;
  v_student jsonb;
begin
  if p_login !~ '^[A-Za-z0-9._@-]{2,100}$' then raise exception 'invalid login'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='ouro_moderno_api_key' limit 1;
  if v_key is null then raise exception 'ouro_moderno_api_key not configured'; end if;
  v_resp := extensions.http((
    'GET'::extensions.http_method,
    'https://meuappdecursos.com.br/ws/v2/alunos'::varchar,
    array[
      extensions.http_header('Authorization','Basic '||encode(convert_to(v_key||':','UTF8'),'base64')),
      extensions.http_header('Accept','application/json')
    ],
    null::varchar,null::varchar
  )::extensions.http_request);
  if v_resp.status <> 200 or position('application/json' in coalesce(v_resp.content_type,'')) = 0 then
    return jsonb_build_object('ok',false,'http_status',v_resp.status,'error','ouro_students_unavailable');
  end if;
  v_body := v_resp.content::jsonb;
  select value into v_student
  from jsonb_array_elements(coalesce(v_body->'data','[]'::jsonb))
  where lower(trim(value->>'usuario')) = lower(trim(p_login))
  limit 1;
  if v_student is null then return jsonb_build_object('ok',false,'http_status',200,'error','student_not_found'); end if;
  return jsonb_build_object('ok',true,'http_status',200,'student',v_student);
end;$function$
;


-- private.ouro_api_student_courses(p_student_id text)
CREATE OR REPLACE FUNCTION private.ouro_api_student_courses(p_student_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'private', 'extensions', 'vault'
AS $function$
declare
  v_key text;
  v_resp extensions.http_response;
begin
  if p_student_id !~ '^[0-9]+$' then raise exception 'invalid student id'; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name='ouro_moderno_api_key' limit 1;
  if v_key is null then raise exception 'ouro_moderno_api_key not configured'; end if;
  v_resp := extensions.http((
    'GET'::extensions.http_method,
    ('https://meuappdecursos.com.br/ws/v2/alunos/cursos/' || p_student_id)::varchar,
    array[
      extensions.http_header('Authorization','Basic ' || encode(convert_to(v_key || ':','UTF8'),'base64')),
      extensions.http_header('Accept','application/json')
    ],
    null::varchar,
    null::varchar
  )::extensions.http_request);
  return jsonb_build_object('http_status',v_resp.status,'content_type',v_resp.content_type,'body',v_resp.content::jsonb);
end;
$function$
;


-- private.ouro_form_encode(p_value text)
CREATE OR REPLACE FUNCTION private.ouro_form_encode(p_value text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_bytes bytea;
  v_out text := '';
  v_i integer;
  v_b integer;
begin
  if p_value is null or p_value = '' then
    return '';
  end if;

  v_bytes := convert_to(p_value, 'UTF8');

  for v_i in 0..length(v_bytes)-1 loop
    v_b := get_byte(v_bytes, v_i);
    if (v_b between 48 and 57)
       or (v_b between 65 and 90)
       or (v_b between 97 and 122)
       or v_b in (45,46,95,126) then
      v_out := v_out || chr(v_b);
    elsif v_b = 32 then
      v_out := v_out || '+';
    else
      v_out := v_out || '%' || upper(lpad(to_hex(v_b),2,'0'));
    end if;
  end loop;

  return v_out;
end;
$function$
;


-- private.ouro_portal_target_courses(p_queue_id uuid)
CREATE OR REPLACE FUNCTION private.ouro_portal_target_courses(p_queue_id uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  v_course_name text;
  v_ids text[];
begin
  select coalesce(c.name, li.metadata->>'course_name')
    into v_course_name
  from public.portal_enrollment_queue q
  join public.lead_interests li on li.id=q.interest_id
  left join public.courses c on c.id=q.course_id
  where q.id=p_queue_id;

  if coalesce(v_course_name,'')='' then
    return '{}'::text[];
  end if;

  select coalesce(array_agg(s.ouro_course_id order by s.first_order),'{}'::text[])
    into v_ids
  from (
    select m.ouro_course_id, min(m.module_order) as first_order
    from public.portal_formation_catalog f
    join public.portal_formation_module_ouro_map m
      on m.formation_slug=f.formation_slug
    where private.portal_name_key(f.formation_name)=private.portal_name_key(v_course_name)
      and coalesce(m.ouro_course_id,'') ~ '^[0-9]+$'
    group by m.ouro_course_id
  ) s;

  return coalesce(v_ids,'{}'::text[]);
end;
$function$
;


-- private.ouro_portal_unit_token(p_unit_id text)
CREATE OR REPLACE FUNCTION private.ouro_portal_unit_token(p_unit_id text DEFAULT '751'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'extensions', 'vault'
AS $function$
declare
  v_key text;
  v_resp extensions.http_response;
  v_body jsonb;
  v_token text;
begin
  if p_unit_id !~ '^[0-9]+$' then
    return jsonb_build_object('ok',false,'error','invalid_unit_id');
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='ouro_moderno_api_key'
  limit 1;

  if v_key is null then
    return jsonb_build_object('ok',false,'error','ouro_api_key_missing');
  end if;

  v_resp := extensions.http((
    'GET'::extensions.http_method,
    ('https://meuappdecursos.com.br/ws/v2/unidades/token/'||p_unit_id)::varchar,
    array[
      extensions.http_header('Authorization','Basic '||encode(convert_to(v_key||':','UTF8'),'base64')),
      extensions.http_header('Accept','application/json')
    ],
    null::varchar,
    null::varchar
  )::extensions.http_request);

  if v_resp.status <> 200 then
    return jsonb_build_object('ok',false,'error','unit_token_http_error','http_status',v_resp.status);
  end if;

  begin
    v_body := v_resp.content::jsonb;
  exception when others then
    return jsonb_build_object('ok',false,'error','unit_token_non_json','http_status',v_resp.status);
  end;

  v_token := coalesce(v_body->'data'->>'token',v_body->>'token');
  if coalesce(v_token,'')='' then
    return jsonb_build_object('ok',false,'error','unit_token_missing','http_status',v_resp.status);
  end if;

  return jsonb_build_object('ok',true,'token',v_token);
end;
$function$
;


-- private.ouro_provision_portal_enrollment(p_queue_id uuid)
CREATE OR REPLACE FUNCTION private.ouro_provision_portal_enrollment(p_queue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'extensions', 'vault'
AS $function$
declare
  q public.portal_enrollment_queue%rowtype;
  li public.lead_interests%rowtype;
  l public.leads%rowtype;
  v_key text;
  v_token_result jsonb;
  v_unit_token text;
  v_student_lookup jsonb;
  v_student_id text;
  v_student_name text;
  v_login text;
  v_cpf text;
  v_rg text;
  v_birth_iso text;
  v_birth_br text;
  v_phone text;
  v_email text;
  v_zip text;
  v_street text;
  v_number text;
  v_neighborhood text;
  v_city text;
  v_state text;
  v_form text;
  v_resp extensions.http_response;
  v_body jsonb;
  v_target_courses text[];
  v_current_courses text[] := '{}'::text[];
  v_missing_courses text[] := '{}'::text[];
  v_contract_ids text[] := '{}'::text[];
  v_snapshot jsonb;
  v_boundary text := '----LCPortalOuroBoundary2026';
  v_payload text;
  v_slot_id uuid;
  v_class_id uuid;
  v_enrollment_id uuid;
  v_all_present boolean := false;
  v_created_student boolean := false;
  v_error text;
  v_temp_password text;
  v_credential_store jsonb;
begin
  select * into q
  from public.portal_enrollment_queue
  where id=p_queue_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'error','queue_not_found');
  end if;

  if q.status in ('matriculada_ouro','matriculada_manual') and q.ouro_student_id is not null and cardinality(q.ouro_contract_ids)>0 then
    return jsonb_build_object(
      'ok',true,
      'already_complete',true,
      'student_id',q.ouro_student_id,
      'contract_ids',to_jsonb(q.ouro_contract_ids),
      'course_ids',to_jsonb(q.ouro_course_ids)
    );
  end if;

  if q.status not in ('aprovada_secretaria','em_cadastro_ouro','paga_aguardando_matricula') then
    return jsonb_build_object('ok',false,'error','queue_not_ready','status',q.status);
  end if;

  select * into li from public.lead_interests where id=q.interest_id;
  select * into l from public.leads where id=q.lead_id;

  update public.portal_enrollment_queue
     set status='em_cadastro_ouro',
         ouro_attempt_count=ouro_attempt_count+1,
         ouro_last_attempt_at=now(),
         ouro_last_error=null,
         ouro_last_response='{}'::jsonb,
         updated_at=now()
   where id=q.id;

  v_target_courses := private.ouro_portal_target_courses(q.id);
  if coalesce(cardinality(v_target_courses),0)=0 then
    v_error := 'ouro_course_mapping_missing';
    update public.portal_enrollment_queue
       set ouro_last_error=v_error,
           ouro_last_response=jsonb_build_object('stage','mapping'),
           updated_at=now()
     where id=q.id;
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','mapping','error',v_error));
    return jsonb_build_object('ok',false,'error',v_error,'stage','mapping');
  end if;

  v_student_id := q.ouro_student_id;

  if coalesce(v_student_id,'')='' then
    select osl.ouro_student_id
      into v_student_id
    from public.ouro_student_links osl
    where osl.lead_id=q.lead_id
      and osl.ouro_account_id='751'
    order by osl.updated_at desc
    limit 1;
  end if;

  if coalesce(v_student_id,'')='' then
    select r.ouro_student_id
      into v_student_id
    from private.ouro_students_registry r
    where r.lead_id=q.lead_id
      and r.ouro_account_id='751'
    order by r.last_seen_at desc
    limit 1;
  end if;

  v_cpf := regexp_replace(coalesce(li.metadata#>>'{student,cpf}',l.cpf,''),'\D','','g');
  v_rg := regexp_replace(coalesce(li.metadata#>>'{student,rg}',l.rg,''),'[^0-9A-Za-z]','','g');
  v_student_name := trim(coalesce(li.metadata#>>'{student,full_name}',l.full_name,''));
  v_birth_iso := coalesce(li.metadata#>>'{student,birth_date}',l.birth_date::text);
  v_phone := regexp_replace(coalesce(li.metadata#>>'{student,whatsapp}',l.whatsapp,''),'\D','','g');
  v_email := trim(coalesce(l.email,''));
  v_zip := regexp_replace(coalesce(li.metadata#>>'{student,address,zip_code}',l.zip_code,''),'\D','','g');
  v_street := trim(coalesce(li.metadata#>>'{student,address,street}',''));
  v_number := trim(coalesce(li.metadata#>>'{student,address,number}',''));
  v_neighborhood := trim(coalesce(li.metadata#>>'{student,address,neighborhood}',l.neighborhood,''));
  v_city := trim(coalesce(li.metadata#>>'{student,address,city}',''));
  v_state := upper(trim(coalesce(li.metadata#>>'{student,address,state}','')));

  if coalesce(v_student_id,'')='' and length(v_cpf)=11 then
    begin
      v_student_lookup := private.ouro_api_student_by_login(v_cpf);
      if coalesce((v_student_lookup->>'ok')::boolean,false) then
        v_student_id := v_student_lookup->'student'->>'id';
      end if;
    exception when others then
      v_student_lookup := jsonb_build_object('ok',false,'error','lookup_failed');
    end;
  end if;

  if coalesce(v_student_id,'')='' then
    if length(v_cpf)<>11 then
      v_error := 'student_cpf_required_for_ouro_auto';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_last_response=jsonb_build_object('stage','student','reason','cpf_missing'),
             updated_at=now()
       where id=q.id;
      insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','student','error',v_error));
      return jsonb_build_object('ok',false,'error',v_error,'stage','student');
    end if;

    if v_student_name='' or v_birth_iso is null or v_birth_iso !~ '^\d{4}-\d{2}-\d{2}$'
       or length(v_phone)<10 or length(v_rg)<5
       or length(v_zip)<>8 or v_street='' or v_number='' or v_neighborhood='' or v_city='' or v_state !~ '^[A-Z]{2}$' then
      v_error := 'student_data_incomplete_for_ouro';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_last_response=jsonb_build_object('stage','student','reason','required_fields_missing'),
             updated_at=now()
       where id=q.id;
      insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','student','error',v_error));
      return jsonb_build_object('ok',false,'error',v_error,'stage','student');
    end if;

    select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name='ouro_moderno_api_key'
    limit 1;

    if v_key is null then
      v_error := 'ouro_api_key_missing';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_last_response=jsonb_build_object('stage','config'),
             updated_at=now()
       where id=q.id;
      return jsonb_build_object('ok',false,'error',v_error,'stage','config');
    end if;

    v_token_result := private.ouro_portal_unit_token('751');
    if not coalesce((v_token_result->>'ok')::boolean,false) then
      v_error := coalesce(v_token_result->>'error','unit_token_failed');
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_last_response=jsonb_build_object('stage','unit_token','http_status',v_token_result->'http_status'),
             updated_at=now()
       where id=q.id;
      return jsonb_build_object('ok',false,'error',v_error,'stage','unit_token');
    end if;
    v_unit_token := v_token_result->>'token';

    v_birth_br := to_char(to_date(v_birth_iso,'YYYY-MM-DD'),'DD/MM/YYYY');

    v_form :=
      'token='||private.ouro_form_encode(v_unit_token)||
      '&nome='||private.ouro_form_encode(v_student_name)||
      '&data_nascimento='||private.ouro_form_encode(v_birth_br)||
      '&email='||private.ouro_form_encode(v_email)||
      '&fone='||private.ouro_form_encode(v_phone)||
      '&doc_cpf='||private.ouro_form_encode(v_cpf)||
      '&doc_rg='||private.ouro_form_encode(v_rg)||
      '&celular='||private.ouro_form_encode(v_phone)||
      '&pais='||private.ouro_form_encode('Brasil')||
      '&uf='||private.ouro_form_encode(v_state)||
      '&cidade='||private.ouro_form_encode(v_city)||
      '&endereco='||private.ouro_form_encode(trim(v_street||' '||v_number))||
      '&complemento='||
      '&bairro='||private.ouro_form_encode(v_neighborhood)||
      '&cep='||private.ouro_form_encode(v_zip);

    v_resp := extensions.http((
      'POST'::extensions.http_method,
      'https://meuappdecursos.com.br/ws/v2/alunos'::varchar,
      array[
        extensions.http_header('Authorization','Basic '||encode(convert_to(v_key||':','UTF8'),'base64')),
        extensions.http_header('Accept','application/json')
      ],
      'application/x-www-form-urlencoded'::varchar,
      v_form::varchar
    )::extensions.http_request);

    begin
      v_body := v_resp.content::jsonb;
    exception when others then
      v_body := '{}'::jsonb;
    end;

    if v_resp.status<>200 or coalesce(v_body->>'status','false')<>'true' or coalesce(v_body->'data'->>'id','')='' then
      v_error := 'ouro_student_create_failed';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_last_response=jsonb_build_object('stage','create_student','http_status',v_resp.status,'api_status',v_body->>'status','info',v_body->>'info'),
             updated_at=now()
       where id=q.id;
      insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','create_student','error',v_error,'http_status',v_resp.status,'info',v_body->>'info'));
      return jsonb_build_object('ok',false,'error',v_error,'stage','create_student','http_status',v_resp.status,'info',v_body->>'info');
    end if;

    v_student_id := v_body->'data'->>'id';
    v_login := coalesce(v_body->'data'->>'usuario',v_cpf);
    v_temp_password := coalesce(v_body->'data'->>'senha','');
    if v_temp_password <> '' then
      v_credential_store := private.portal_store_initial_credential(q.id,v_student_id,v_login,v_temp_password);
      if not coalesce((v_credential_store->>'ok')::boolean,false) then
        insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
        values(auth.uid(),'portal_credential_capture_failed','portal_enrollment_queue',q.id,jsonb_build_object('student_id',v_student_id,'error',v_credential_store->>'error'));
      end if;
    else
      v_credential_store := jsonb_build_object('ok',false,'error','password_not_returned');
      insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'portal_credential_capture_failed','portal_enrollment_queue',q.id,jsonb_build_object('student_id',v_student_id,'error','password_not_returned'));
    end if;
    v_created_student := true;
  else
    v_login := v_cpf;
  end if;

  update public.portal_enrollment_queue
     set ouro_student_id=v_student_id,
         ouro_created_student=ouro_created_student or v_created_student,
         updated_at=now()
   where id=q.id;

  insert into public.ouro_student_links(
    ouro_account_id,ouro_account_name,ouro_student_id,lead_id,
    student_name,email,phone,login,last_event_name,last_event_at,updated_at
  )
  values(
    '751','LIVE CONNECT ILHÉUS',v_student_id,q.lead_id,
    nullif(v_student_name,''),nullif(v_email,''),nullif(v_phone,''),nullif(v_login,''),
    'portal_auto_enrollment',now(),now()
  )
  on conflict (ouro_account_id,ouro_student_id) do update
     set lead_id=excluded.lead_id,
         student_name=coalesce(excluded.student_name,public.ouro_student_links.student_name),
         email=coalesce(excluded.email,public.ouro_student_links.email),
         phone=coalesce(excluded.phone,public.ouro_student_links.phone),
         login=coalesce(excluded.login,public.ouro_student_links.login),
         last_event_name='portal_auto_enrollment',
         last_event_at=now(),
         updated_at=now();

  begin
    v_snapshot := private.ouro_api_student_courses(v_student_id);
  exception when others then
    v_snapshot := '{}'::jsonb;
  end;

  if coalesce((v_snapshot->>'http_status')::int,0)=200 then
    select coalesce(array_agg(distinct x->>'id') filter(where coalesce(x->>'id','')<>''),'{}'::text[])
      into v_current_courses
    from jsonb_array_elements(coalesce(v_snapshot->'body'->'data','[]'::jsonb)) x;
  end if;

  select coalesce(array_agg(t.course_id order by t.ord),'{}'::text[])
    into v_missing_courses
  from unnest(v_target_courses) with ordinality as t(course_id,ord)
  where not (t.course_id = any(coalesce(v_current_courses,'{}'::text[])));

  if coalesce(cardinality(v_missing_courses),0)>0 then
    if v_key is null then
      select decrypted_secret into v_key
      from vault.decrypted_secrets
      where name='ouro_moderno_api_key'
      limit 1;
    end if;

    if coalesce(v_unit_token,'')='' then
      v_token_result := private.ouro_portal_unit_token('751');
      if not coalesce((v_token_result->>'ok')::boolean,false) then
        v_error := coalesce(v_token_result->>'error','unit_token_failed');
        update public.portal_enrollment_queue
           set ouro_last_error=v_error,
               ouro_last_response=jsonb_build_object('stage','unit_token'),
               updated_at=now()
         where id=q.id;
        return jsonb_build_object('ok',false,'error',v_error,'stage','unit_token');
      end if;
      v_unit_token := v_token_result->>'token';
    end if;

    v_payload :=
      '--'||v_boundary||E'\r\n'||
      'Content-Disposition: form-data; name="token"'||E'\r\n\r\n'||
      v_unit_token||E'\r\n'||
      '--'||v_boundary||E'\r\n'||
      'Content-Disposition: form-data; name="cursos"'||E'\r\n\r\n'||
      array_to_string(v_missing_courses,',')||E'\r\n'||
      '--'||v_boundary||'--'||E'\r\n';

    v_resp := extensions.http((
      'POST'::extensions.http_method,
      ('https://meuappdecursos.com.br/ws/v2/alunos/matricula/'||v_student_id)::varchar,
      array[
        extensions.http_header('Authorization','Basic '||encode(convert_to(v_key||':','UTF8'),'base64')),
        extensions.http_header('Accept','application/json')
      ],
      ('multipart/form-data; boundary='||v_boundary)::varchar,
      v_payload::varchar
    )::extensions.http_request);

    begin
      v_body := v_resp.content::jsonb;
    exception when others then
      v_body := '{}'::jsonb;
    end;

    if v_resp.status<>200 or coalesce(v_body->>'status','false')<>'true' then
      v_error := 'ouro_course_enrollment_failed';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_course_ids=v_target_courses,
             ouro_last_response=jsonb_build_object('stage','enroll_courses','http_status',v_resp.status,'api_status',v_body->>'status','info',v_body->>'info'),
             updated_at=now()
       where id=q.id;
      insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','enroll_courses','error',v_error,'http_status',v_resp.status,'info',v_body->>'info','course_ids',to_jsonb(v_missing_courses)));
      return jsonb_build_object('ok',false,'error',v_error,'stage','enroll_courses','http_status',v_resp.status,'info',v_body->>'info');
    end if;
  end if;

  begin
    v_snapshot := private.ouro_api_student_courses(v_student_id);
  exception when others then
    v_snapshot := '{}'::jsonb;
  end;

  if coalesce((v_snapshot->>'http_status')::int,0)=200 then
    select
      coalesce(array_agg(distinct x->'contrato'->>'id') filter(where coalesce(x->'contrato'->>'id','')<>''),'{}'::text[]),
      count(distinct x->>'id') filter(where (x->>'id') = any(v_target_courses)) = cardinality(v_target_courses)
    into v_contract_ids,v_all_present
    from jsonb_array_elements(coalesce(v_snapshot->'body'->'data','[]'::jsonb)) x
    where (x->>'id') = any(v_target_courses);
  end if;

  if not coalesce(v_all_present,false) then
    v_error := 'ouro_enrollment_verification_failed';
    update public.portal_enrollment_queue
       set ouro_last_error=v_error,
           ouro_course_ids=v_target_courses,
           ouro_contract_ids=coalesce(v_contract_ids,'{}'::text[]),
           ouro_last_response=jsonb_build_object('stage','verify','student_id',v_student_id,'course_ids',to_jsonb(v_target_courses)),
           updated_at=now()
     where id=q.id;
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',q.id,jsonb_build_object('stage','verify','error',v_error,'student_id',v_student_id,'course_ids',to_jsonb(v_target_courses)));
    return jsonb_build_object('ok',false,'error',v_error,'stage','verify','student_id',v_student_id);
  end if;

  if lower(trim(coalesce(li.metadata->>'modality','presencial')))='presencial' then
    select cs.id,cs.class_id,cs.enrollment_id
      into v_slot_id,v_class_id,v_enrollment_id
    from public.class_slots cs
    where cs.id=q.reserved_slot_id
      and cs.state='reserved'
    for update;

    if v_slot_id is null or v_class_id is null or v_enrollment_id is null then
      v_error := 'reservation_not_found_after_ouro';
      update public.portal_enrollment_queue
         set ouro_last_error=v_error,
             ouro_student_id=v_student_id,
             ouro_course_ids=v_target_courses,
             ouro_contract_ids=coalesce(v_contract_ids,'{}'::text[]),
             ouro_last_response=jsonb_build_object('stage','local_finalize','student_id',v_student_id,'contract_ids',to_jsonb(v_contract_ids)),
             updated_at=now()
       where id=q.id;
      return jsonb_build_object('ok',false,'error',v_error,'stage','local_finalize','student_id',v_student_id,'contract_ids',to_jsonb(v_contract_ids));
    end if;

    update public.classes
       set manual_reserved=greatest(coalesce(manual_reserved,0)-1,0),
           updated_at=now()
     where id=v_class_id;

    update public.enrollments e
       set class_id=v_class_id,
           weekday=c.weekday,
           start_time=c.start_time,
           end_time=c.end_time,
           schedule_text=(case c.weekday
             when 1 then 'Segunda-feira'
             when 2 then 'Terça-feira'
             when 3 then 'Quarta-feira'
             when 4 then 'Quinta-feira'
             when 5 then 'Sexta-feira'
             when 6 then 'Sábado'
             else 'Dia '||c.weekday::text end)
             ||' • '||to_char(c.start_time,'HH24:MI')||' às '||to_char(c.end_time,'HH24:MI'),
           enrolled_at=coalesce(e.enrolled_at,now())
      from public.classes c
     where e.id=v_enrollment_id
       and c.id=v_class_id;

    update public.class_slots
       set state='occupied',
           note='Matrícula confirmada automaticamente pela integração Ouro Moderno',
           updated_at=now()
     where id=v_slot_id;
  else
    select e.id into v_enrollment_id
    from public.enrollments e
    where e.lead_id=q.lead_id
      and (q.course_id is null or e.course_id=q.course_id)
      and e.cancelled_at is null
    order by e.created_at desc
    limit 1;

    update public.enrollments
       set enrolled_at=coalesce(enrolled_at,now())
     where id=v_enrollment_id;
  end if;

  update public.portal_enrollment_queue
     set status='matriculada_ouro',
         processed_at=now(),
         completed_at=coalesce(completed_at,now()),
         ouro_student_id=v_student_id,
         ouro_course_ids=v_target_courses,
         ouro_contract_ids=coalesce(v_contract_ids,'{}'::text[]),
         ouro_last_error=null,
         ouro_last_response=jsonb_build_object(
           'stage','complete',
           'mode','automatic',
           'student_id',v_student_id,
           'course_ids',to_jsonb(v_target_courses),
           'contract_ids',to_jsonb(coalesce(v_contract_ids,'{}'::text[]))
         ),
         updated_at=now()
   where id=q.id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    'portal_ouro_enrollment_success',
    'portal_enrollment_queue',
    q.id,
    jsonb_build_object(
      'student_id',v_student_id,
      'created_student',v_created_student,
      'course_ids',to_jsonb(v_target_courses),
      'contract_ids',to_jsonb(coalesce(v_contract_ids,'{}'::text[]))
    )
  );

  return jsonb_build_object(
    'ok',true,
    'mode','automatic',
    'student_id',v_student_id,
    'created_student',v_created_student,
    'course_ids',to_jsonb(v_target_courses),
    'contract_ids',to_jsonb(coalesce(v_contract_ids,'{}'::text[])),
    'status','matriculada_ouro',
    'access_credentials_captured',coalesce((v_credential_store->>'ok')::boolean,false)
  );
exception when others then
  v_error := left(sqlerrm,500);
  begin
    update public.portal_enrollment_queue
       set ouro_last_error=v_error,
           ouro_last_response=jsonb_build_object('stage','exception'),
           updated_at=now()
     where id=p_queue_id;
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'portal_ouro_enrollment_failed','portal_enrollment_queue',p_queue_id,jsonb_build_object('stage','exception','error',v_error));
  exception when others then
    null;
  end;
  return jsonb_build_object('ok',false,'error','internal_ouro_provision_error','detail',v_error);
end;
$function$
;


-- private.portal_auto_process_paid_enrollment(p_queue_id uuid)
CREATE OR REPLACE FUNCTION private.portal_auto_process_paid_enrollment(p_queue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public'
AS $function$
declare
  q public.portal_enrollment_queue%rowtype;
  li public.lead_interests%rowtype;
  v_modality text;
  v_class public.classes%rowtype;
  v_enrollment_id uuid;
  v_slot_id uuid;
  v_remaining integer;
  v_ouro jsonb;
begin
  select * into q
  from public.portal_enrollment_queue
  where id=p_queue_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'error','queue_not_found');
  end if;

  if q.status in ('matriculada_ouro','matriculada_manual') then
    return jsonb_build_object('ok',true,'already_complete',true,'status',q.status);
  end if;

  if q.status not in ('paga_aguardando_matricula','em_cadastro_ouro') then
    return jsonb_build_object('ok',false,'error','queue_not_paid','status',q.status);
  end if;

  select * into li from public.lead_interests where id=q.interest_id;
  v_modality := lower(trim(coalesce(li.metadata->>'modality','presencial')));

  select e.id into v_enrollment_id
  from public.enrollments e
  where e.lead_id=q.lead_id
    and (q.course_id is null or e.course_id=q.course_id)
    and e.cancelled_at is null
  order by e.created_at desc
  limit 1;

  if v_enrollment_id is null then
    update public.portal_enrollment_queue
       set ouro_last_error='enrollment_not_found',
           updated_at=now()
     where id=q.id;
    return jsonb_build_object('ok',false,'error','enrollment_not_found');
  end if;

  if v_modality='presencial' then
    if q.reserved_slot_id is null then
      if q.preferred_class_id is null then
        update public.portal_enrollment_queue
           set status='horario_indisponivel',
               ouro_last_error='preferred_class_required',
               updated_at=now()
         where id=q.id;
        return jsonb_build_object('ok',false,'error','preferred_class_required');
      end if;

      select * into v_class
      from public.classes
      where id=q.preferred_class_id
        and (q.course_id is null or course_id=q.course_id)
      for update;

      if not found or v_class.status::text<>'aberta' or coalesce(v_class.source_hidden,false) then
        update public.portal_enrollment_queue
           set status='horario_indisponivel',
               ouro_last_error='class_unavailable',
               updated_at=now()
         where id=q.id;
        return jsonb_build_object('ok',false,'error','class_unavailable');
      end if;

      select remaining_seats into v_remaining
      from public.class_capacity_summary
      where id=v_class.id;

      if coalesce(v_remaining,0)<=0 then
        update public.portal_enrollment_queue
           set status='horario_indisponivel',
               ouro_last_error='class_full',
               updated_at=now()
         where id=q.id;
        return jsonb_build_object('ok',false,'error','class_full');
      end if;

      select cs.id into v_slot_id
      from public.class_slots cs
      where cs.class_id=v_class.id
        and cs.state='available'
      order by cs.slot_no
      for update skip locked
      limit 1;

      if v_slot_id is null then
        update public.portal_enrollment_queue
           set status='horario_indisponivel',
               ouro_last_error='class_full',
               updated_at=now()
         where id=q.id;
        return jsonb_build_object('ok',false,'error','class_full');
      end if;

      update public.class_slots
         set state='reserved',
             enrollment_id=v_enrollment_id,
             note='Reserva automática após pagamento - Portal Live Connect',
             updated_at=now()
       where id=v_slot_id;

      update public.classes
         set manual_reserved=coalesce(manual_reserved,0)+1,
             updated_at=now()
       where id=v_class.id;

      update public.portal_enrollment_queue
         set reserved_slot_id=v_slot_id,
             status='em_cadastro_ouro',
             ouro_started_at=coalesce(ouro_started_at,now()),
             ouro_last_error=null,
             updated_at=now()
       where id=q.id;

      update public.lead_interests
         set metadata=jsonb_set(
           coalesce(metadata,'{}'::jsonb),
           '{auto_reserved_at}',
           to_jsonb(now()::text),
           true
         )
       where id=q.interest_id;
    else
      update public.portal_enrollment_queue
         set status='em_cadastro_ouro',
             ouro_started_at=coalesce(ouro_started_at,now()),
             ouro_last_error=null,
             updated_at=now()
       where id=q.id;
    end if;
  else
    update public.portal_enrollment_queue
       set status='em_cadastro_ouro',
           ouro_started_at=coalesce(ouro_started_at,now()),
           ouro_last_error=null,
           updated_at=now()
     where id=q.id;
  end if;

  v_ouro := private.ouro_provision_portal_enrollment(q.id);
  return v_ouro;
exception when others then
  update public.portal_enrollment_queue
     set ouro_last_error=left(sqlerrm,500),
         updated_at=now()
   where id=p_queue_id;
  return jsonb_build_object('ok',false,'error','automatic_enrollment_exception','detail',left(sqlerrm,500));
end;
$function$
;


-- private.portal_name_key(p_value text)
CREATE OR REPLACE FUNCTION private.portal_name_key(p_value text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select regexp_replace(
    translate(
      lower(coalesce(p_value,'')),
      'áàâãäéèêëíìîïóòôõöúùûüçñ',
      'aaaaaeeeeiiiiooooouuuucn'
    ),
    '[^a-z0-9]+',
    '',
    'g'
  );
$function$
;


-- private.portal_purge_expired_initial_credentials()
CREATE OR REPLACE FUNCTION private.portal_purge_expired_initial_credentials()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private'
AS $function$
declare v_count integer;
begin
  update private.portal_access_credentials
     set password_cipher=null,
         token_hash=null,
         token_expires_at=null,
         updated_at=now()
   where password_cipher is not null
     and created_at < now()-interval '72 hours';

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$
;


-- private.portal_retry_automatic_enrollments(p_limit integer)
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
  for r in
    select q.id
    from public.portal_enrollment_queue q
    where q.status in ('paga_aguardando_matricula','em_cadastro_ouro')
      and q.ouro_attempt_count < 6
      and (
        q.ouro_last_attempt_at is null
        or q.ouro_last_attempt_at < now()-interval '5 minutes'
      )
    order by q.updated_at
    limit greatest(1,least(coalesce(p_limit,10),50))
    for update skip locked
  loop
    v_result := private.portal_auto_process_paid_enrollment(r.id);
    v_count := v_count+1;
  end loop;

  return v_count;
end;
$function$
;


-- private.portal_store_initial_credential(p_queue_id uuid, p_ouro_student_id text, p_username text, p_password text)
CREATE OR REPLACE FUNCTION private.portal_store_initial_credential(p_queue_id uuid, p_ouro_student_id text, p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'private', 'public', 'extensions', 'vault'
AS $function$
declare
  v_q public.portal_enrollment_queue%rowtype;
  v_l public.leads%rowtype;
  v_key text;
begin
  if p_queue_id is null or coalesce(p_ouro_student_id,'')='' or coalesce(p_username,'')='' or coalesce(p_password,'')='' then
    return jsonb_build_object('ok',false,'error','credential_payload_invalid');
  end if;

  select * into v_q from public.portal_enrollment_queue where id=p_queue_id;
  if not found then
    return jsonb_build_object('ok',false,'error','queue_not_found');
  end if;

  select * into v_l from public.leads where id=v_q.lead_id;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='portal_credentials_encryption_key'
  limit 1;

  if v_key is null then
    return jsonb_build_object('ok',false,'error','credential_key_missing');
  end if;

  insert into private.portal_access_credentials(
    queue_id,lead_id,ouro_student_id,username,password_cipher,email,whatsapp,
    token_hash,token_expires_at,viewed_at,email_status,updated_at
  )
  values(
    p_queue_id,v_q.lead_id,p_ouro_student_id,p_username,
    extensions.pgp_sym_encrypt(p_password,v_key,'cipher-algo=aes256'),
    nullif(trim(coalesce(v_l.email,'')),''),
    nullif(regexp_replace(coalesce(v_l.whatsapp,''),'\D','','g'),''),
    null,null,null,
    'not_applicable',
    now()
  )
  on conflict (queue_id) do update
     set ouro_student_id=excluded.ouro_student_id,
         username=excluded.username,
         password_cipher=excluded.password_cipher,
         email=excluded.email,
         whatsapp=excluded.whatsapp,
         token_hash=null,
         token_expires_at=null,
         viewed_at=null,
         email_status='not_applicable',
         email_sent_at=null,
         email_last_error=null,
         updated_at=now();

  return jsonb_build_object(
    'ok',true,
    'username',p_username,
    'email_available',nullif(trim(coalesce(v_l.email,'')),'') is not null,
    'whatsapp_available',nullif(regexp_replace(coalesce(v_l.whatsapp,''),'\D','','g'),'') is not null
  );
end;
$function$
;


-- public.school_secretary_mark_credentials_whatsapp_sent(p_queue_id uuid)
CREATE OR REPLACE FUNCTION public.school_secretary_mark_credentials_whatsapp_sent(p_queue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_c private.portal_access_credentials%rowtype;
begin
  if not public.is_secretaria() then
    raise exception 'forbidden';
  end if;

  select * into v_c
  from private.portal_access_credentials
  where queue_id=p_queue_id
  for update;

  if not found then
    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'portal_whatsapp_existing_access_sent','portal_enrollment_queue',p_queue_id,'{}'::jsonb);

    return jsonb_build_object('ok',true,'mode','existing_student','sent_at',now());
  end if;

  update private.portal_access_credentials
     set whatsapp_sent_at=coalesce(whatsapp_sent_at,now()),
         password_cipher=null,
         token_hash=null,
         token_expires_at=null,
         updated_at=now()
   where id=v_c.id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    'portal_whatsapp_credentials_sent',
    'portal_enrollment_queue',
    p_queue_id,
    jsonb_build_object('ouro_student_id',v_c.ouro_student_id,'username',v_c.username)
  );

  return jsonb_build_object('ok',true,'mode','new_student','sent_at',now());
end;
$function$
;


-- public.school_secretary_pending_credentials(p_limit integer)
CREATE OR REPLACE FUNCTION public.school_secretary_pending_credentials(p_limit integer DEFAULT 100)
 RETURNS TABLE(queue_id uuid, full_name text, whatsapp text, course_name text, ouro_student_id text, username text, credential_mode text, credential_status text, completed_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
  select
    q.id,
    l.full_name,
    l.whatsapp,
    coalesce(c.name,li.metadata->>'course_name'),
    q.ouro_student_id,
    coalesce(pac.username,osl.login,regexp_replace(coalesce(l.cpf,''),'\D','','g')),
    case when pac.id is null then 'existing_student' else 'new_student' end,
    case
      when pac.whatsapp_sent_at is not null then 'enviada'
      when pac.password_cipher is not null then 'pendente_envio'
      when pac.id is null then 'pendente_envio_acesso_existente'
      else 'senha_inicial_indisponivel'
    end,
    q.completed_at
  from public.portal_enrollment_queue q
  join public.leads l on l.id=q.lead_id
  join public.lead_interests li on li.id=q.interest_id
  left join public.courses c on c.id=q.course_id
  left join private.portal_access_credentials pac on pac.queue_id=q.id
  left join lateral (
    select x.login
    from public.ouro_student_links x
    where x.ouro_account_id='751'
      and x.ouro_student_id=q.ouro_student_id
    order by x.updated_at desc
    limit 1
  ) osl on true
  where public.is_secretaria()
    and q.status in ('matriculada_ouro','matriculada_manual')
    and (pac.whatsapp_sent_at is null or pac.id is null)
  order by q.completed_at desc nulls last
  limit greatest(1,least(coalesce(p_limit,100),500));
$function$
;


-- public.school_secretary_prepare_first_access(p_queue_id uuid)
CREATE OR REPLACE FUNCTION public.school_secretary_prepare_first_access(p_queue_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions', 'vault'
AS $function$
declare
  v_q public.portal_enrollment_queue%rowtype;
  v_l public.leads%rowtype;
  v_c private.portal_access_credentials%rowtype;
  v_key text;
  v_password text;
  v_message text;
  v_phone text;
  v_username text;
begin
  if not public.is_secretaria() then
    raise exception 'forbidden';
  end if;

  select * into v_q
  from public.portal_enrollment_queue
  where id=p_queue_id;

  if not found then
    raise exception 'not_found';
  end if;

  if v_q.status not in ('matriculada_ouro','matriculada_manual') then
    return jsonb_build_object('ok',false,'error','enrollment_not_completed');
  end if;

  select * into v_l
  from public.leads
  where id=v_q.lead_id;

  select * into v_c
  from private.portal_access_credentials
  where queue_id=p_queue_id
  for update;

  if not found then
    select osl.login into v_username
    from public.ouro_student_links osl
    where osl.ouro_account_id='751'
      and osl.ouro_student_id=v_q.ouro_student_id
    order by osl.updated_at desc
    limit 1;

    v_username := coalesce(nullif(v_username,''),regexp_replace(coalesce(v_l.cpf,''),'\D','','g'));

    v_message :=
      'Sua matrícula foi confirmada na Live Connect.'||E'\n\n'||
      'Seu acesso ao ambiente de estudos já está ativo.'||E'\n\n'||
      'Usuário: '||coalesce(v_username,'')||E'\n\n'||
      'Como este usuário já existia na plataforma, utilize sua senha atual. '||
      'Se não lembrar, toque em "Esqueceu a senha?" na tela de acesso.'||E'\n\n'||
      'Acesso: https://ead.ouromoderno.com.br/';

    return jsonb_build_object(
      'ok',true,
      'mode','existing_student',
      'username',v_username,
      'password',null,
      'message',v_message,
      'whatsapp',v_l.whatsapp,
      'already_sent',false
    );
  end if;

  if v_c.whatsapp_sent_at is not null then
    return jsonb_build_object(
      'ok',true,
      'mode','already_sent',
      'username',v_c.username,
      'password',null,
      'message',null,
      'whatsapp',coalesce(v_c.whatsapp,v_l.whatsapp),
      'already_sent',true,
      'sent_at',v_c.whatsapp_sent_at
    );
  end if;

  if v_c.password_cipher is null then
    return jsonb_build_object(
      'ok',false,
      'error','initial_password_unavailable',
      'username',v_c.username,
      'whatsapp',coalesce(v_c.whatsapp,v_l.whatsapp)
    );
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name='portal_credentials_encryption_key'
  limit 1;

  if v_key is null then
    return jsonb_build_object('ok',false,'error','credential_key_missing');
  end if;

  v_password := extensions.pgp_sym_decrypt(v_c.password_cipher,v_key);
  v_phone := coalesce(v_c.whatsapp,v_l.whatsapp);

  v_message :=
    'Sua matrícula foi confirmada na Live Connect.'||E'\n\n'||
    'Seu acesso ao ambiente de estudos já está disponível.'||E'\n\n'||
    'Usuário: '||v_c.username||E'\n'||
    'Senha inicial: '||v_password||E'\n\n'||
    'Acesso: https://ead.ouromoderno.com.br/'||E'\n\n'||
    'No primeiro login, a plataforma solicitará que você crie uma nova senha pessoal.';

  update private.portal_access_credentials
     set whatsapp_prepared_at=now(),
         updated_at=now()
   where id=v_c.id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(
    auth.uid(),
    'portal_whatsapp_credentials_prepared',
    'portal_enrollment_queue',
    p_queue_id,
    jsonb_build_object(
      'ouro_student_id',v_c.ouro_student_id,
      'username',v_c.username
    )
  );

  return jsonb_build_object(
    'ok',true,
    'mode','new_student',
    'username',v_c.username,
    'password',v_password,
    'message',v_message,
    'whatsapp',v_phone,
    'already_sent',false
  );
end;
$function$
;


-- public.sync_portal_enrollment_queue_payment()
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
begin
  select e.lead_id,e.course_id,e.commercial_mode
    into v_lead,v_course,v_mode
  from public.enrollments e
  where e.id=new.enrollment_id;

  if v_lead is null then
    return new;
  end if;

  if (
    ((v_mode='profissao_rapida' and new.kind='profissao_rapida_total')
      or (v_mode<>'profissao_rapida' and new.kind='matricula'))
    and (new.status::text='pago' or lower(coalesce(new.provider_status,'')) in ('approved','paid'))
  ) or (
    v_mode<>'profissao_rapida'
    and new.kind='matricula'
    and new.status::text='isento'
  ) then
    for v_queue_id in
      update public.portal_enrollment_queue q
         set status='paga_aguardando_matricula',
             payment_approved_at=coalesce(q.payment_approved_at,now()),
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
end;
$function$
;

drop trigger if exists trg_sync_portal_enrollment_queue_payment on public.payments;
create trigger trg_sync_portal_enrollment_queue_payment
after insert or update of status, provider_status on public.payments
for each row execute function public.sync_portal_enrollment_queue_payment();

revoke execute on function public.school_secretary_prepare_first_access(uuid) from public, anon;
revoke execute on function public.school_secretary_mark_credentials_whatsapp_sent(uuid) from public, anon;
revoke execute on function public.school_secretary_pending_credentials(integer) from public, anon;

grant execute on function public.school_secretary_prepare_first_access(uuid) to authenticated;
grant execute on function public.school_secretary_mark_credentials_whatsapp_sent(uuid) to authenticated;
grant execute on function public.school_secretary_pending_credentials(integer) to authenticated;

do $$
begin
  perform cron.unschedule(jobid)
  from cron.job
  where jobname='portal-auto-enrollment-retry';

  perform cron.schedule(
    'portal-auto-enrollment-retry',
    '*/5 * * * *',
    'select private.portal_retry_automatic_enrollments(10);'
  );

  perform cron.unschedule(jobid)
  from cron.job
  where jobname='portal-purge-expired-initial-credentials';

  perform cron.schedule(
    'portal-purge-expired-initial-credentials',
    '17 * * * *',
    'select private.portal_purge_expired_initial_credentials();'
  );
end $$;
