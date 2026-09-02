-- Jovem Aprendiz: cadastro manual exige turma escolhida
-- Aplicado em produção em 2026-09-02

CREATE OR REPLACE FUNCTION public.admin_manual_registration_create(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_kind text := lower(coalesce(nullif(trim(p_payload->>'registration_type'),''),'course'));
  v_lead_id uuid;
  v_requested_lead uuid;
  v_full_name text := nullif(trim(p_payload->>'full_name'),'');
  v_phone text := regexp_replace(coalesce(p_payload->>'whatsapp',''),'\D','','g');
  v_email text := nullif(lower(trim(p_payload->>'email')),'');
  v_birth date;
  v_age integer;
  v_minor boolean;
  v_rg text := nullif(trim(p_payload->>'rg'),'');
  v_cpf text := nullif(regexp_replace(coalesce(p_payload->>'cpf',''),'\D','','g'),'');
  v_zip text := nullif(regexp_replace(coalesce(p_payload->>'zip_code',''),'\D','','g'),'');
  v_address text := nullif(trim(p_payload->>'address'),'');
  v_neighborhood text := nullif(trim(p_payload->>'neighborhood'),'');
  v_guardian_name text := nullif(trim(p_payload->>'guardian_name'),'');
  v_guardian_phone text := regexp_replace(coalesce(p_payload->>'guardian_whatsapp',''),'\D','','g');
  v_guardian_birth date;
  v_guardian_rg text := nullif(trim(p_payload->>'guardian_rg'),'');
  v_guardian_cpf text := nullif(regexp_replace(coalesce(p_payload->>'guardian_cpf',''),'\D','','g'),'');
  v_course public.courses%rowtype;
  v_enrollment uuid;
  v_interest uuid;
  v_form uuid;
  v_contract uuid;
  v_template public.contract_templates%rowtype;
  v_price uuid;
  v_fee numeric:=0;
  v_month numeric:=0;
  v_first numeric:=0;
  v_beauty numeric:=0;
  v_installments integer:=12;
  v_total numeric:=0;
  v_mode text:=coalesce(nullif(trim(p_payload->>'commercial_mode'),''),'tradicional');
  v_payment_method text:=nullif(trim(p_payload->>'payment_method'),'');
  v_enroll_status text:=coalesce(nullif(trim(p_payload->>'enrollment_payment_status'),''),'pendente');
  v_first_status text:=coalesce(nullif(trim(p_payload->>'first_month_payment_status'),''),'pendente');
  v_due integer;
  v_class_id uuid;
  v_class public.classes%rowtype;
  v_note text:=nullif(trim(p_payload->>'note'),'');
  v_contract_no text;
  v_school_status text;
  v_shift text;
  v_selected_class text;
  v_selected_class_label text;
  v_currently_studying boolean;
  v_city text:=nullif(trim(p_payload->>'city'),'');
  v_state text:=upper(nullif(trim(p_payload->>'state'),''));
  v_street text:=nullif(trim(p_payload->>'street'),'');
  v_number text:=nullif(trim(p_payload->>'number'),'');
  v_snapshot jsonb;
begin
  if not public.is_admin_comercial() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  if v_kind not in ('course','young_apprentice') then
    raise exception 'invalid_registration_type' using errcode='22023';
  end if;

  if v_full_name is null then raise exception 'full_name_required' using errcode='22023'; end if;
  if length(v_phone) in (10,11) then v_phone:='55'||v_phone; end if;
  if length(v_phone)<12 or length(v_phone)>13 then raise exception 'invalid_whatsapp' using errcode='22023'; end if;
  if v_guardian_phone<>'' and length(v_guardian_phone) in (10,11) then v_guardian_phone:='55'||v_guardian_phone; end if;

  if nullif(p_payload->>'birth_date','') is not null then
    begin v_birth:=(p_payload->>'birth_date')::date; exception when others then raise exception 'invalid_birth_date' using errcode='22023'; end;
    v_age:=date_part('year',age(current_date,v_birth))::int;
    v_minor:=v_age<18;
  end if;

  if nullif(p_payload->>'guardian_birth_date','') is not null then
    begin v_guardian_birth:=(p_payload->>'guardian_birth_date')::date; exception when others then raise exception 'invalid_guardian_birth_date' using errcode='22023'; end;
  end if;

  if nullif(p_payload->>'lead_id','') is not null then
    begin v_requested_lead:=(p_payload->>'lead_id')::uuid; exception when others then v_requested_lead:=null; end;
  end if;

  if v_requested_lead is not null then
    select id into v_lead_id from public.leads where id=v_requested_lead for update;
  end if;

  if v_lead_id is null then
    select id into v_lead_id
    from public.leads
    where whatsapp_normalized=v_phone or whatsapp=v_phone
    order by (deleted_at is null) desc,updated_at desc
    limit 1
    for update;
  end if;

  if v_address is null and v_street is not null then
    v_address:=concat_ws(', ',v_street,v_number);
    if v_city is not null then v_address:=v_address||' - '||v_city||coalesce('/'||v_state,''); end if;
  end if;

  if v_lead_id is null then
    insert into public.leads(
      full_name,whatsapp,email,age,birth_date,rg,cpf,address,neighborhood,zip_code,
      guardian_name,guardian_whatsapp,guardian_birth_date,guardian_rg,guardian_cpf,
      source,status,lead_score,archived,deleted_at,professional_goal,currently_studying
    )
    values(
      v_full_name,v_phone,v_email,v_age,v_birth,v_rg,v_cpf,v_address,v_neighborhood,v_zip,
      v_guardian_name,nullif(v_guardian_phone,''),v_guardian_birth,v_guardian_rg,v_guardian_cpf,
      'admin_manual_registration',
      case when v_kind='young_apprentice' then 'pre_inscricao'::public.lead_status else 'matricula_confirmada'::public.lead_status end,
      case when v_kind='young_apprentice' then 80 else 100 end,false,null,
      case when v_kind='young_apprentice' then 'Projeto Jovem Aprendiz' else null end,
      case when v_kind='young_apprentice' then true else null end
    )
    returning id into v_lead_id;
  else
    update public.leads set
      full_name=v_full_name,
      whatsapp=v_phone,
      email=coalesce(v_email,email),
      age=coalesce(v_age,age),
      birth_date=coalesce(v_birth,birth_date),
      rg=coalesce(v_rg,rg),
      cpf=coalesce(v_cpf,cpf),
      address=coalesce(v_address,address),
      neighborhood=coalesce(v_neighborhood,neighborhood),
      zip_code=coalesce(v_zip,zip_code),
      guardian_name=coalesce(v_guardian_name,guardian_name),
      guardian_whatsapp=coalesce(nullif(v_guardian_phone,''),guardian_whatsapp),
      guardian_birth_date=coalesce(v_guardian_birth,guardian_birth_date),
      guardian_rg=coalesce(v_guardian_rg,guardian_rg),
      guardian_cpf=coalesce(v_guardian_cpf,guardian_cpf),
      professional_goal=case when v_kind='young_apprentice' then 'Projeto Jovem Aprendiz' else professional_goal end,
      currently_studying=case when v_kind='young_apprentice' then true else currently_studying end,
      status=case when v_kind='young_apprentice' then status else 'matricula_confirmada'::public.lead_status end,
      archived=false,deleted_at=null,updated_at=now()
    where id=v_lead_id;
  end if;

  if v_kind='young_apprentice' then
    v_school_status:=coalesce(nullif(trim(p_payload->>'school_status'),''),'medio');
    v_shift:=coalesce(nullif(trim(p_payload->>'available_shift'),''),'indiferente');
    v_selected_class:=nullif(trim(p_payload->>'selected_class'),'');
    v_selected_class_label:=case v_selected_class
      when 'terca_0900_1000' then 'Terça-feira • 09:00 às 10:00'
      when 'quinta_1400_1500' then 'Quinta-feira • 14:00 às 15:00'
      else null
    end;
    if v_selected_class_label is null then raise exception 'invalid_selected_class' using errcode='22023'; end if;
    if v_school_status not in ('fundamental','medio','medio_concluido','nao_estuda') then
      raise exception 'invalid_school_status' using errcode='22023';
    end if;
    if v_shift not in ('manha','tarde','noite','indiferente') then
      raise exception 'invalid_available_shift' using errcode='22023';
    end if;
    v_currently_studying:=v_school_status not in ('medio_concluido','nao_estuda');
    update public.leads set currently_studying=v_currently_studying where id=v_lead_id;

    insert into public.lead_interests(lead_id,course_id,interest_type,source,metadata)
    values(
      v_lead_id,null,'jovem_aprendiz','admin_manual_registration',
      jsonb_build_object(
        'manual',true,'school_status',v_school_status,'available_shift',v_shift,
        'selected_class',v_selected_class,'selected_class_label',v_selected_class_label,
        'currently_studying',v_currently_studying,'created_by',auth.uid()
      )
    )
    returning id into v_interest;

    v_snapshot:=jsonb_build_object(
      'student_name',v_full_name,'age',v_age,'birth_date',v_birth,'whatsapp',v_phone,
      'rg',v_rg,'cpf',v_cpf,'address',v_address,'street',v_street,'number',v_number,
      'neighborhood',v_neighborhood,'city',v_city,'state',v_state,'zip_code',v_zip,
      'guardian_name',v_guardian_name,'guardian_whatsapp',nullif(v_guardian_phone,''),
      'guardian_rg',v_guardian_rg,'guardian_cpf',v_guardian_cpf,'guardian_birth_date',v_guardian_birth,
      'currently_studying',v_currently_studying,'school_status',v_school_status,
      'available_shift',v_shift,'selected_class',v_selected_class,'selected_class_label',v_selected_class_label,
      'project','Projeto Jovem Aprendiz','submitted_at',now(),
      'source','admin_manual_registration'
    );

    insert into public.young_apprentice_registration_forms(lead_id,interest_id,data_snapshot)
    values(v_lead_id,v_interest,v_snapshot)
    returning id into v_form;

    insert into public.lead_activities(lead_id,activity_type,description,metadata)
    values(v_lead_id,'inscricao_jovem_aprendiz_manual','Projeto Jovem Aprendiz — ficha criada manualmente no Admin — turma: '||v_selected_class_label,
           jsonb_build_object('form_id',v_form,'interest_id',v_interest,'selected_class',v_selected_class,'selected_class_label',v_selected_class_label));

    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'manual_young_apprentice_create','young_apprentice_form',v_form,
           jsonb_build_object('lead_id',v_lead_id));

    return jsonb_build_object(
      'ok',true,'registration_type','young_apprentice','lead_id',v_lead_id,
      'form_id',v_form,'document_type','young_apprentice_form','document_id',v_form
    );
  end if;

  begin v_course.id:=(p_payload->>'course_id')::uuid; exception when others then v_course.id:=null; end;
  if v_course.id is null then raise exception 'course_required' using errcode='22023'; end if;
  select * into v_course from public.courses where id=v_course.id and active=true;
  if v_course.id is null then raise exception 'course_not_found' using errcode='P0002'; end if;

  if exists(select 1 from public.enrollments where lead_id=v_lead_id and course_id=v_course.id and cancelled_at is null) then
    raise exception 'student_already_enrolled_in_course' using errcode='23505';
  end if;

  if nullif(p_payload->>'class_id','') is not null then
    begin v_class_id:=(p_payload->>'class_id')::uuid; exception when others then raise exception 'invalid_class' using errcode='22023'; end;
  end if;

  if nullif(p_payload->>'due_day','') is not null then
    v_due:=(p_payload->>'due_day')::int;
    if v_due not in (5,10,15,20,25,30) then raise exception 'invalid_due_day' using errcode='22023'; end if;
  end if;

  if v_course.type='pago' then
    select id,enrollment_fee,monthly_fee,beauty_surcharge,installments
      into v_price,v_fee,v_month,v_beauty,v_installments
    from public.pricing_versions
    where active=true and valid_from<=now() and (valid_until is null or valid_until>now())
    order by valid_from desc limit 1;
    if v_price is null then raise exception 'pricing_not_found' using errcode='P0002'; end if;
    if upper(v_course.name) like '%BELEZA%' then v_month:=v_month+coalesce(v_beauty,40); end if;

    if nullif(p_payload->>'enrollment_fee','') is not null then v_fee=(p_payload->>'enrollment_fee')::numeric; end if;
    if nullif(p_payload->>'monthly_fee','') is not null then v_month=(p_payload->>'monthly_fee')::numeric; end if;
    v_first:=v_month;
    if nullif(p_payload->>'first_monthly_fee','') is not null then v_first=(p_payload->>'first_monthly_fee')::numeric; end if;
    if nullif(p_payload->>'installments','') is not null then v_installments=greatest(1,(p_payload->>'installments')::int); end if;

    if v_mode not in ('tradicional','profissao_rapida') then raise exception 'invalid_commercial_mode' using errcode='22023'; end if;
    if v_enroll_status not in ('pendente','pago','isento','cortesia') then raise exception 'invalid_payment_status' using errcode='22023'; end if;
    if v_first_status not in ('pendente','pago','isento','cortesia') then raise exception 'invalid_payment_status' using errcode='22023'; end if;
    if v_payment_method is not null and v_payment_method not in ('pix','credito','debito','dinheiro') then raise exception 'invalid_payment_method' using errcode='22023'; end if;

    v_total:=v_fee+(v_month*v_installments);
    if nullif(p_payload->>'course_total','') is not null then v_total=(p_payload->>'course_total')::numeric; end if;
  else
    v_fee:=0;v_month:=0;v_first:=0;v_total:=0;v_installments:=1;
    v_mode:='tradicional';v_enroll_status:='isento';v_first_status:='isento';v_payment_method:=null;v_price:=null;
  end if;

  insert into public.enrollments(
    lead_id,course_id,pricing_version_id,
    enrollment_fee_snapshot,first_monthly_fee_snapshot,monthly_fee_snapshot,
    payment_method,enrollment_payment_status,first_month_payment_status,
    due_day,start_date,schedule_text,note,commercial_mode,installments_snapshot,course_total_snapshot
  )
  values(
    v_lead_id,v_course.id,v_price,
    v_fee,v_first,v_month,
    v_payment_method::public.payment_method,v_enroll_status::public.payment_status,v_first_status::public.payment_status,
    v_due,nullif(p_payload->>'start_date','')::date,nullif(trim(p_payload->>'schedule_text'),''),
    v_note,v_mode,v_installments,v_total
  )
  returning id into v_enrollment;

  if v_class_id is not null then
    perform public.admin_transfer_enrollment_class(v_enrollment,v_class_id);
  end if;

  if v_course.type='pago' then
    if v_mode='profissao_rapida' then
      insert into public.payments(enrollment_id,kind,amount,method,status)
      values(v_enrollment,'profissao_rapida_total',v_total,v_payment_method::public.payment_method,v_enroll_status::public.payment_status);
    else
      insert into public.payments(enrollment_id,kind,amount,method,status)
      values
        (v_enrollment,'matricula',v_fee,v_payment_method::public.payment_method,v_enroll_status::public.payment_status),
        (v_enrollment,'primeira_mensalidade',v_first,v_payment_method::public.payment_method,v_first_status::public.payment_status);
    end if;
  end if;

  insert into public.lead_interests(lead_id,course_id,interest_type,source,metadata)
  values(
    v_lead_id,v_course.id,
    case when v_course.type='gratuito' then 'curso_gratuito' else 'curso_pago' end,
    'admin_manual_registration',
    jsonb_build_object('manual',true,'enrollment_id',v_enrollment,'commercial_mode',v_mode,'created_by',auth.uid())
  )
  returning id into v_interest;

  insert into public.lead_activities(lead_id,activity_type,description,metadata)
  values(
    v_lead_id,
    case when v_course.type='gratuito' then 'matricula_gratuita_manual' else 'matricula_manual' end,
    'Matrícula manual criada no Admin — '||v_course.name,
    jsonb_build_object('enrollment_id',v_enrollment,'course_id',v_course.id,'interest_id',v_interest)
  );

  if v_course.type='gratuito' then
    v_form:=public.ensure_free_registration_form_internal(v_enrollment);

    insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'manual_free_enrollment_create','enrollment',v_enrollment,
           jsonb_build_object('lead_id',v_lead_id,'course_id',v_course.id,'form_id',v_form));

    return jsonb_build_object(
      'ok',true,'registration_type','course','course_type','gratuito','lead_id',v_lead_id,
      'enrollment_id',v_enrollment,'form_id',v_form,'document_type','free_registration_form','document_id',v_form
    );
  end if;

  select * into v_template
  from public.contract_templates
  where active=true
  order by version desc,created_at desc
  limit 1;
  if v_template.id is null then raise exception 'contract_template_not_found' using errcode='P0002'; end if;

  if v_class_id is not null then select * into v_class from public.classes where id=v_class_id; end if;

  v_contract_no:='LC-'||to_char(current_date,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));

  insert into public.contracts(
    lead_id,enrollment_id,contract_template_version_id,contract_number,
    data_snapshot,values_snapshot,text_snapshot,status
  )
  values(
    v_lead_id,v_enrollment,v_template.id,v_contract_no,
    jsonb_build_object(
      'student_name',v_full_name,'whatsapp',v_phone,'email',v_email,'age',v_age,'birth_date',v_birth,
      'rg',v_rg,'cpf',v_cpf,'address',v_address,'neighborhood',v_neighborhood,'zip_code',v_zip,
      'guardian_name',v_guardian_name,'guardian_whatsapp',nullif(v_guardian_phone,''),
      'guardian_birth_date',v_guardian_birth,'guardian_rg',v_guardian_rg,'guardian_cpf',v_guardian_cpf,
      'course',v_course.name,'weekday',v_class.weekday,'start_time',v_class.start_time,'end_time',v_class.end_time,
      'start_date',coalesce(nullif(p_payload->>'start_date','')::date,v_class.start_date),
      'schedule_text',coalesce(nullif(trim(p_payload->>'schedule_text'),''),v_class.secretary_label),
      'payment_method',v_payment_method,'commercial_mode',v_mode
    ),
    jsonb_build_object(
      'due_day',v_due,'enrollment_fee',v_fee,'first_monthly_fee',v_first,'monthly_fee',v_month,
      'installments',v_installments,'total_value',v_total
    ),
    v_template.content,'preenchido'
  )
  returning id into v_contract;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'manual_paid_enrollment_create','enrollment',v_enrollment,
         jsonb_build_object('lead_id',v_lead_id,'course_id',v_course.id,'contract_id',v_contract));

  return jsonb_build_object(
    'ok',true,'registration_type','course','course_type','pago','lead_id',v_lead_id,
    'enrollment_id',v_enrollment,'contract_id',v_contract,'contract_number',v_contract_no,
    'document_type','contract','document_id',v_contract
  );
end
$function$
;

revoke all on function public.admin_get_contract(uuid) from public,anon;
grant execute on function public.admin_get_contract(uuid) to authenticated;
revoke all on function public.admin_manual_registration_create(jsonb) from public,anon;
grant execute on function public.admin_manual_registration_create(jsonb) to authenticated;
