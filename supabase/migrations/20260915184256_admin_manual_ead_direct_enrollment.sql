CREATE OR REPLACE FUNCTION public.admin_manual_ead_direct_enrollment(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'private', 'extensions', 'vault'
AS $$
declare
  v_full_name text := nullif(trim(p_payload->>'full_name'),'');
  v_phone text := regexp_replace(coalesce(p_payload->>'whatsapp',''),'\\D','','g');
  v_email text := nullif(lower(trim(p_payload->>'email')),'');
  v_cpf text := nullif(regexp_replace(coalesce(p_payload->>'cpf',''),'\\D','','g'),'');
  v_rg text := nullif(regexp_replace(coalesce(p_payload->>'rg',''),'[^0-9A-Za-z]','','g'),'');
  v_birth date;
  v_age integer;
  v_zip text := nullif(regexp_replace(coalesce(p_payload->>'zip_code',''),'\\D','','g'),'');
  v_street text := nullif(trim(p_payload->>'street'),'');
  v_number text := nullif(trim(p_payload->>'number'),'');
  v_neighborhood text := nullif(trim(p_payload->>'neighborhood'),'');
  v_city text := nullif(trim(p_payload->>'city'),'');
  v_state text := upper(nullif(trim(p_payload->>'state'),''));
  v_address text;
  v_course_id uuid;
  v_course public.courses%rowtype;
  v_lead_id uuid;
  v_enrollment_id uuid;
  v_interest_id uuid;
  v_contract_id uuid;
  v_queue_id uuid;
  v_ouro_result jsonb;
  v_price uuid;
  v_fee numeric := 0;
  v_month numeric := 0;
  v_first numeric := 0;
  v_installments integer := 12;
  v_total numeric := 0;
  v_payment_method text := coalesce(nullif(trim(p_payload->>'payment_method'),''),'pix');
  v_due_day integer := coalesce(nullif(p_payload->>'due_day','')::int, 10);
  v_template public.contract_templates%rowtype;
  v_contract_no text;
  v_master_user_id uuid := '62e02abd-0e94-40e1-9364-3b2c5f80dbed';
begin
  if v_full_name is null or length(v_full_name) < 3 then
    return jsonb_build_object('ok', false, 'error', 'Nome completo é obrigatório');
  end if;

  if length(v_phone) in (10,11) then v_phone := '55'||v_phone; end if;
  if length(v_phone) < 12 or length(v_phone) > 13 then
    return jsonb_build_object('ok', false, 'error', 'WhatsApp inválido');
  end if;

  if v_email is null or v_email !~ '^[^@]+@[^@]+\.[^@]+$' then
    return jsonb_build_object('ok', false, 'error', 'E-mail válido é obrigatório para integração com o Ouro Moderno');
  end if;

  if v_cpf is null or length(v_cpf) <> 11 then
    return jsonb_build_object('ok', false, 'error', 'CPF de 11 dígitos é obrigatório');
  end if;

  if v_rg is null or length(v_rg) < 4 then
    return jsonb_build_object('ok', false, 'error', 'RG é obrigatório');
  end if;

  begin
    v_birth := (p_payload->>'birth_date')::date;
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'Data de nascimento inválida (use AAAA-MM-DD)');
  end;
  v_age := date_part('year', age(current_date, v_birth))::int;

  if v_zip is null or length(v_zip) <> 8 then
    return jsonb_build_object('ok', false, 'error', 'CEP de 8 dígitos é obrigatório');
  end if;

  if v_street is null or v_number is null or v_neighborhood is null or v_city is null or v_state is null then
    return jsonb_build_object('ok', false, 'error', 'Endereço completo é obrigatório (rua, número, bairro, cidade, UF)');
  end if;
  v_address := concat_ws(', ', v_street, v_number) || ' - ' || v_neighborhood || ' - ' || v_city || '/' || v_state;

  begin
    v_course_id := (p_payload->>'course_id')::uuid;
  exception when others then
    v_course_id := null;
  end;
  if v_course_id is null then
    return jsonb_build_object('ok', false, 'error', 'Selecione um curso válido');
  end if;
  select * into v_course from public.courses where id=v_course_id and active=true;
  if v_course.id is null then
    return jsonb_build_object('ok', false, 'error', 'Curso não encontrado ou inativo');
  end if;

  -- 1. Cria ou atualiza o Lead
  select id into v_lead_id from public.leads 
  where cpf = v_cpf or whatsapp = v_phone or whatsapp_normalized = v_phone 
  order by (deleted_at is null) desc, updated_at desc limit 1;

  if v_lead_id is null then
    insert into public.leads(
      full_name, whatsapp, email, age, birth_date, rg, cpf, address, neighborhood, zip_code,
      source, status, lead_score, archived
    ) values (
      v_full_name, v_phone, v_email, v_age, v_birth, v_rg, v_cpf, v_address, v_neighborhood, v_zip,
      'admin_manual_ead', 'matricula_confirmada'::public.lead_status, 100, false
    ) returning id into v_lead_id;
  else
    update public.leads set
      full_name = v_full_name,
      whatsapp = v_phone,
      email = v_email,
      age = v_age,
      birth_date = v_birth,
      rg = v_rg,
      cpf = v_cpf,
      address = v_address,
      neighborhood = v_neighborhood,
      zip_code = v_zip,
      status = 'matricula_confirmada'::public.lead_status,
      archived = false,
      deleted_at = null,
      updated_at = now()
    where id = v_lead_id;
  end if;

  -- 2. Valores financeiros e pricing
  select id, enrollment_fee, monthly_fee, installments
    into v_price, v_fee, v_month, v_installments
  from public.pricing_versions
  where active=true and valid_from<=now() and (valid_until is null or valid_until>now())
  order by valid_from desc limit 1;

  if nullif(p_payload->>'enrollment_fee','') is not null then v_fee := (p_payload->>'enrollment_fee')::numeric; end if;
  if nullif(p_payload->>'monthly_fee','') is not null then v_month := (p_payload->>'monthly_fee')::numeric; end if;
  v_first := v_month;
  if nullif(p_payload->>'first_monthly_fee','') is not null then v_first := (p_payload->>'first_monthly_fee')::numeric; end if;
  if nullif(p_payload->>'installments','') is not null then v_installments := greatest(1, (p_payload->>'installments')::int); end if;
  v_total := v_fee + (v_month * v_installments);

  -- 3. Inserir Matrícula
  insert into public.enrollments(
    lead_id, course_id, pricing_version_id,
    enrollment_fee_snapshot, first_monthly_fee_snapshot, monthly_fee_snapshot,
    payment_method, enrollment_payment_status, first_month_payment_status,
    due_day, start_date, schedule_text, note, commercial_mode, installments_snapshot, course_total_snapshot,
    enrolled_at
  ) values (
    v_lead_id, v_course.id, v_price,
    v_fee, v_first, v_month,
    v_payment_method::public.payment_method, 'pago'::public.payment_status, 'pago'::public.payment_status,
    v_due_day, current_date, 'EAD - sem horário presencial', coalesce(p_payload->>'note', 'Matrícula Manual EAD Direta'),
    'tradicional', v_installments, v_total, now()
  ) returning id into v_enrollment_id;

  -- Pagamentos
  insert into public.payments(enrollment_id, kind, amount, method, status)
  values
    (v_enrollment_id, 'matricula', v_fee, v_payment_method::public.payment_method, 'pago'::public.payment_status),
    (v_enrollment_id, 'primeira_mensalidade', v_first, v_payment_method::public.payment_method, 'pago'::public.payment_status);

  -- 4. Contrato
  select * into v_template from public.contract_templates where active=true order by version desc, created_at desc limit 1;
  v_contract_no := 'LC-' || to_char(current_date,'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  if v_template.id is not null then
    insert into public.contracts(
      lead_id, enrollment_id, contract_template_version_id, contract_number,
      data_snapshot, values_snapshot, text_snapshot, status
    ) values (
      v_lead_id, v_enrollment_id, v_template.id, v_contract_no,
      jsonb_build_object(
        'student_name', v_full_name, 'whatsapp', v_phone, 'email', v_email, 'age', v_age, 'birth_date', v_birth,
        'rg', v_rg, 'cpf', v_cpf, 'address', v_address, 'neighborhood', v_neighborhood, 'zip_code', v_zip,
        'course', v_course.name, 'schedule_text', 'EAD - sem horário presencial',
        'payment_method', v_payment_method, 'commercial_mode', 'tradicional'
      ),
      jsonb_build_object('due_day', v_due_day, 'enrollment_fee', v_fee, 'first_monthly_fee', v_first, 'monthly_fee', v_month, 'installments', v_installments, 'total_value', v_total),
      v_template.content, 'preenchido'
    ) returning id into v_contract_id;
  end if;

  -- 5. Inserir lead_interests
  insert into public.lead_interests(
    lead_id, course_id, interest_type, source, metadata
  ) values (
    v_lead_id, v_course.id, 'matricula_portal', 'admin_manual_ead',
    jsonb_build_object(
      'modality', 'EAD',
      'course_name', v_course.name,
      'enrollment_id', v_enrollment_id,
      'manual', true,
      'student', jsonb_build_object(
        'full_name', v_full_name,
        'whatsapp', v_phone,
        'email', v_email,
        'cpf', v_cpf,
        'rg', v_rg,
        'birth_date', v_birth::text,
        'address', jsonb_build_object(
          'zip_code', v_zip,
          'street', v_street,
          'number', v_number,
          'neighborhood', v_neighborhood,
          'city', v_city,
          'state', v_state
        )
      )
    )
  ) returning id into v_interest_id;

  -- 6. Inserir na fila portal_enrollment_queue
  insert into public.portal_enrollment_queue(
    interest_id, lead_id, course_id, status, created_at, updated_at
  ) values (
    v_interest_id, v_lead_id, v_course.id, 'paga_aguardando_matricula', now(), now()
  )
  on conflict (interest_id) do update
    set status = 'paga_aguardando_matricula',
        updated_at = now()
  returning id into v_queue_id;

  -- 7. Executar o provisionamento real no Ouro Moderno!
  v_ouro_result := private.ouro_provision_portal_enrollment(v_queue_id);

  -- Registrar log de auditoria
  insert into public.audit_logs(user_id, action, entity_type, entity_id, metadata)
  values(
    v_master_user_id,
    'admin_manual_ead_direct_enrollment',
    'portal_enrollment_queue',
    v_queue_id,
    jsonb_build_object(
      'lead_id', v_lead_id,
      'enrollment_id', v_enrollment_id,
      'course_id', v_course.id,
      'course_name', v_course.name,
      'ouro_result', v_ouro_result
    )
  );

  return jsonb_build_object(
    'ok', coalesce((v_ouro_result->>'ok')::boolean, false),
    'queue_id', v_queue_id,
    'lead_id', v_lead_id,
    'enrollment_id', v_enrollment_id,
    'contract_id', v_contract_id,
    'contract_number', v_contract_no,
    'student_name', v_full_name,
    'student_login', v_cpf,
    'whatsapp', v_phone,
    'course_name', v_course.name,
    'ouro', v_ouro_result
  );
end;
$$;

revoke all on function public.admin_manual_ead_direct_enrollment(jsonb) from public;
grant execute on function public.admin_manual_ead_direct_enrollment(jsonb) to anon, authenticated, service_role;
