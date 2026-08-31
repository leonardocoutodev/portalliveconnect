-- V4.1 — Editor 360° do aluno e múltiplos cursos

create unique index if not exists enrollments_one_active_course_per_student_uidx
on public.enrollments(lead_id,course_id)
where cancelled_at is null;

CREATE OR REPLACE FUNCTION public.admin_student_add_course(p_lead_id uuid, p_course_id uuid, p_class_id uuid DEFAULT NULL::uuid, p_due_day smallint DEFAULT NULL::smallint, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  c public.courses%rowtype;
  v_price uuid;
  v_fee numeric:=0;
  v_month numeric:=0;
  v_first numeric:=0;
  v_beauty numeric:=0;
  v_installments integer:=12;
  v_enrollment uuid;
begin
  if not public.is_master_admin() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  if not exists(select 1 from public.leads where id=p_lead_id and deleted_at is null) then
    raise exception 'student_not_found' using errcode='P0002';
  end if;

  select * into c from public.courses where id=p_course_id and active=true;
  if c.id is null then raise exception 'course_not_found' using errcode='P0002'; end if;

  if exists(
    select 1 from public.enrollments
    where lead_id=p_lead_id and course_id=p_course_id and cancelled_at is null
  ) then
    raise exception 'student_already_enrolled_in_course' using errcode='23505';
  end if;

  if p_due_day is not null and p_due_day not in (5,10,15,20,25,30) then
    raise exception 'invalid_due_day' using errcode='22023';
  end if;

  if c.type='pago' then
    select id,enrollment_fee,monthly_fee,beauty_surcharge,installments
      into v_price,v_fee,v_month,v_beauty,v_installments
    from public.pricing_versions
    where active=true and valid_from<=now() and (valid_until is null or valid_until>now())
    order by valid_from desc limit 1;

    if v_price is null then raise exception 'pricing_not_found' using errcode='P0002'; end if;
    if upper(c.name) like '%BELEZA%' then v_month:=v_month+coalesce(v_beauty,40); end if;
    v_first:=v_month;
  end if;

  insert into public.enrollments(
    lead_id,course_id,pricing_version_id,
    enrollment_fee_snapshot,first_monthly_fee_snapshot,monthly_fee_snapshot,
    enrollment_payment_status,first_month_payment_status,
    due_day,note,commercial_mode,installments_snapshot,course_total_snapshot
  )
  values(
    p_lead_id,p_course_id,v_price,
    v_fee,v_first,v_month,
    case when c.type='gratuito' then 'isento'::public.payment_status else 'pendente'::public.payment_status end,
    case when c.type='gratuito' then 'isento'::public.payment_status else 'pendente'::public.payment_status end,
    p_due_day,nullif(trim(p_note),''),'tradicional',v_installments,0
  )
  returning id into v_enrollment;

  if c.type='pago' then
    insert into public.payments(enrollment_id,kind,amount,status)
    values
      (v_enrollment,'matricula',v_fee,'pendente'),
      (v_enrollment,'primeira_mensalidade',v_first,'pendente');
  end if;

  insert into public.lead_interests(lead_id,course_id,interest_type,source,metadata)
  values(
    p_lead_id,p_course_id,
    case when c.type='gratuito' then 'curso_gratuito' else 'curso_pago' end,
    'admin_student_editor',
    jsonb_build_object('enrollment_id',v_enrollment,'added_manually',true)
  );

  if p_class_id is not null then
    if not exists(
      select 1 from public.classes cl
      where cl.id=p_class_id and cl.course_id=p_course_id and cl.status in ('aberta','lotada')
    ) then
      raise exception 'class_not_valid_for_course' using errcode='22023';
    end if;
    perform public.admin_transfer_enrollment_class(v_enrollment,p_class_id);
  end if;

  update public.leads
  set status='matricula_confirmada',archived=false,updated_at=now()
  where id=p_lead_id;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'student_course_added','enrollment',v_enrollment,jsonb_build_object('lead_id',p_lead_id,'course_id',p_course_id,'class_id',p_class_id));

  return jsonb_build_object('ok',true,'enrollment_id',v_enrollment,'course_id',p_course_id);
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_student_editor_get(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_lead jsonb;
  v_enrollments jsonb;
  v_courses jsonb;
  v_classes jsonb;
  v_young jsonb;
begin
  if not public.is_master_admin() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select to_jsonb(l) into v_lead
  from public.leads l
  where l.id=p_lead_id and l.deleted_at is null;

  if v_lead is null then
    raise exception 'student_not_found' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.cancelled_at nulls first,x.enrolled_at desc),'[]'::jsonb)
  into v_enrollments
  from (
    select
      e.id as enrollment_id,e.lead_id,e.course_id,c.name as course_name,c.type::text as course_type,
      e.class_id,cl.secretary_label as class_label,cl.course_id as class_course_id,
      e.weekday,e.start_time,e.end_time,e.start_date,e.schedule_text,e.due_day,
      e.payment_method::text as payment_method,
      e.enrollment_payment_status::text as enrollment_payment_status,
      e.first_month_payment_status::text as first_month_payment_status,
      e.enrollment_fee_snapshot,e.first_monthly_fee_snapshot,e.monthly_fee_snapshot,
      e.commercial_mode,e.installments_snapshot,e.course_total_snapshot,e.note,e.enrolled_at,
      e.cancelled_at,e.cancellation_note,fr.id as free_registration_form_id
    from public.enrollments e
    join public.courses c on c.id=e.course_id
    left join public.classes cl on cl.id=e.class_id
    left join public.free_registration_forms fr on fr.enrollment_id=e.id
    where e.lead_id=p_lead_id
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'type',c.type::text,'active',c.active
  ) order by c.type,c.name),'[]'::jsonb)
  into v_courses
  from public.courses c
  where c.active=true
     or exists(
       select 1 from public.enrollments e
       where e.lead_id=p_lead_id and e.course_id=c.id
     );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',cl.id,'course_id',cl.course_id,'label',cl.secretary_label,'weekday',cl.weekday,
    'start_time',cl.start_time,'end_time',cl.end_time,'start_date',cl.start_date,
    'status',cl.status::text,'capacity',cl.capacity,'room_name',cl.room_name,'source_hidden',cl.source_hidden
  ) order by cl.weekday,cl.start_time),'[]'::jsonb)
  into v_classes
  from public.classes cl
  where (
      cl.status in ('aberta','lotada') and coalesce(cl.source_hidden,false)=false
    )
    or exists(
      select 1 from public.enrollments e
      where e.lead_id=p_lead_id and e.class_id=cl.id
    );

  select coalesce(jsonb_agg(jsonb_build_object(
    'form_id',f.id,'status',f.status,'data_snapshot',f.data_snapshot,
    'generated_at',f.generated_at,'printed_at',f.printed_at
  ) order by f.generated_at desc),'[]'::jsonb)
  into v_young
  from public.young_apprentice_registration_forms f
  where f.lead_id=p_lead_id;

  return jsonb_build_object(
    'lead',v_lead,
    'enrollments',v_enrollments,
    'courses',v_courses,
    'classes',v_classes,
    'young_apprentice_forms',v_young
  );
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_student_update_enrollment(p_enrollment_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  olde public.enrollments%rowtype;
  finale public.enrollments%rowtype;
  new_course public.courses%rowtype;
  target_course uuid;
  target_class uuid;
  course_changed boolean:=false;
  class_change_requested boolean:=false;
  v_price uuid;
  v_fee numeric;
  v_month numeric;
  v_first numeric;
  v_beauty numeric;
  v_installments integer;
  v_out jsonb;
begin
  if not public.is_master_admin() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select * into olde
  from public.enrollments
  where id=p_enrollment_id
  for update;

  if olde.id is null then raise exception 'enrollment_not_found' using errcode='P0002'; end if;

  target_course:=case when p_patch ? 'course_id' then (p_patch->>'course_id')::uuid else olde.course_id end;
  course_changed:=target_course is distinct from olde.course_id;

  select * into new_course from public.courses where id=target_course and active=true;
  if new_course.id is null then raise exception 'course_not_found' using errcode='P0002'; end if;

  if exists(
    select 1 from public.enrollments e
    where e.lead_id=olde.lead_id
      and e.course_id=target_course
      and e.cancelled_at is null
      and e.id<>p_enrollment_id
  ) then
    raise exception 'student_already_enrolled_in_course' using errcode='23505';
  end if;

  if p_patch ? 'due_day'
     and nullif(p_patch->>'due_day','') is not null
     and (p_patch->>'due_day')::int not in (5,10,15,20,25,30) then
    raise exception 'invalid_due_day' using errcode='22023';
  end if;

  if p_patch ? 'commercial_mode'
     and p_patch->>'commercial_mode' not in ('tradicional','profissao_rapida') then
    raise exception 'invalid_commercial_mode' using errcode='22023';
  end if;

  if p_patch ? 'payment_method'
     and nullif(p_patch->>'payment_method','') is not null
     and p_patch->>'payment_method' not in ('pix','credito','debito','dinheiro') then
    raise exception 'invalid_payment_method' using errcode='22023';
  end if;

  if p_patch ? 'enrollment_payment_status'
     and p_patch->>'enrollment_payment_status' not in ('pago','pendente','isento','cortesia') then
    raise exception 'invalid_payment_status' using errcode='22023';
  end if;

  if p_patch ? 'first_month_payment_status'
     and p_patch->>'first_month_payment_status' not in ('pago','pendente','isento','cortesia') then
    raise exception 'invalid_payment_status' using errcode='22023';
  end if;

  if course_changed and olde.class_id is not null then
    perform public.admin_remove_enrollment_class(p_enrollment_id);
  end if;

  if course_changed then
    if new_course.type='pago' then
      select id,enrollment_fee,monthly_fee,beauty_surcharge,installments
        into v_price,v_fee,v_month,v_beauty,v_installments
      from public.pricing_versions
      where active=true and valid_from<=now() and (valid_until is null or valid_until>now())
      order by valid_from desc limit 1;

      if v_price is null then raise exception 'pricing_not_found' using errcode='P0002'; end if;
      if upper(new_course.name) like '%BELEZA%' then v_month:=v_month+coalesce(v_beauty,40); end if;
      v_first:=v_month;
    else
      v_price:=null;v_fee:=0;v_month:=0;v_first:=0;v_installments:=12;
    end if;
  else
    v_price:=olde.pricing_version_id;
    v_fee:=olde.enrollment_fee_snapshot;
    v_month:=olde.monthly_fee_snapshot;
    v_first:=olde.first_monthly_fee_snapshot;
    v_installments:=olde.installments_snapshot;
  end if;

  update public.enrollments e set
    course_id=target_course,
    pricing_version_id=case when p_patch ? 'pricing_version_id' then nullif(p_patch->>'pricing_version_id','')::uuid else v_price end,
    enrollment_fee_snapshot=case when p_patch ? 'enrollment_fee_snapshot' then coalesce((p_patch->>'enrollment_fee_snapshot')::numeric,0) else v_fee end,
    first_monthly_fee_snapshot=case when p_patch ? 'first_monthly_fee_snapshot' then coalesce((p_patch->>'first_monthly_fee_snapshot')::numeric,0) else v_first end,
    monthly_fee_snapshot=case when p_patch ? 'monthly_fee_snapshot' then coalesce((p_patch->>'monthly_fee_snapshot')::numeric,0) else v_month end,
    due_day=case when p_patch ? 'due_day' then nullif(p_patch->>'due_day','')::smallint else e.due_day end,
    schedule_text=case when p_patch ? 'schedule_text' then nullif(trim(p_patch->>'schedule_text'),'') else e.schedule_text end,
    start_date=case when p_patch ? 'start_date' then nullif(p_patch->>'start_date','')::date else e.start_date end,
    payment_method=case when p_patch ? 'payment_method' then nullif(p_patch->>'payment_method','')::public.payment_method else e.payment_method end,
    enrollment_payment_status=case
      when p_patch ? 'enrollment_payment_status' then (p_patch->>'enrollment_payment_status')::public.payment_status
      when course_changed and new_course.type='gratuito' then 'isento'::public.payment_status
      when course_changed then 'pendente'::public.payment_status
      else e.enrollment_payment_status
    end,
    first_month_payment_status=case
      when p_patch ? 'first_month_payment_status' then (p_patch->>'first_month_payment_status')::public.payment_status
      when course_changed and new_course.type='gratuito' then 'isento'::public.payment_status
      when course_changed then 'pendente'::public.payment_status
      else e.first_month_payment_status
    end,
    commercial_mode=case when p_patch ? 'commercial_mode' then p_patch->>'commercial_mode' else e.commercial_mode end,
    installments_snapshot=case when p_patch ? 'installments_snapshot' then greatest(1,(p_patch->>'installments_snapshot')::int) else v_installments end,
    course_total_snapshot=case
      when p_patch ? 'course_total_snapshot' then coalesce((p_patch->>'course_total_snapshot')::numeric,0)
      when course_changed then 0
      else e.course_total_snapshot
    end,
    note=case when p_patch ? 'note' then nullif(trim(p_patch->>'note'),'') else e.note end
  where e.id=p_enrollment_id
  returning e.* into finale;

  if new_course.type='pago' then
    if not exists(select 1 from public.payments where enrollment_id=p_enrollment_id and kind='matricula') then
      insert into public.payments(enrollment_id,kind,amount,method,status,paid_at)
      values(
        p_enrollment_id,'matricula',finale.enrollment_fee_snapshot,finale.payment_method,
        finale.enrollment_payment_status,
        case when finale.enrollment_payment_status='pago' then now() else null end
      );
    end if;

    if not exists(select 1 from public.payments where enrollment_id=p_enrollment_id and kind='primeira_mensalidade') then
      insert into public.payments(enrollment_id,kind,amount,method,status,paid_at)
      values(
        p_enrollment_id,'primeira_mensalidade',finale.first_monthly_fee_snapshot,finale.payment_method,
        finale.first_month_payment_status,
        case when finale.first_month_payment_status='pago' then now() else null end
      );
    end if;

    update public.payments
    set amount=finale.enrollment_fee_snapshot,
        method=finale.payment_method,
        status=finale.enrollment_payment_status,
        paid_at=case when finale.enrollment_payment_status='pago' then coalesce(paid_at,now()) else null end
    where enrollment_id=p_enrollment_id
      and kind='matricula'
      and provider_payment_id is null;

    update public.payments
    set amount=finale.first_monthly_fee_snapshot,
        method=finale.payment_method,
        status=finale.first_month_payment_status,
        paid_at=case when finale.first_month_payment_status='pago' then coalesce(paid_at,now()) else null end
    where enrollment_id=p_enrollment_id
      and kind='primeira_mensalidade'
      and provider_payment_id is null;
  else
    update public.payments
    set amount=0,
        method=finale.payment_method,
        status=case when status='pago' then status else 'isento'::public.payment_status end,
        paid_at=case when status='pago' then paid_at else null end
    where enrollment_id=p_enrollment_id
      and kind in ('matricula','primeira_mensalidade')
      and provider_payment_id is null;
  end if;

  class_change_requested:=p_patch ? 'class_id';
  if class_change_requested then
    if nullif(p_patch->>'class_id','') is null then
      perform public.admin_remove_enrollment_class(p_enrollment_id);
    else
      target_class:=(p_patch->>'class_id')::uuid;
      if not exists(
        select 1 from public.classes cl
        where cl.id=target_class and cl.course_id=target_course and cl.status in ('aberta','lotada')
      ) then
        raise exception 'class_not_valid_for_course' using errcode='22023';
      end if;
      perform public.admin_transfer_enrollment_class(p_enrollment_id,target_class);
    end if;
  end if;

  if course_changed then
    insert into public.lead_interests(lead_id,course_id,interest_type,source,metadata)
    values(
      olde.lead_id,target_course,
      case when new_course.type='gratuito' then 'curso_gratuito' else 'curso_pago' end,
      'admin_student_editor',
      jsonb_build_object(
        'enrollment_id',p_enrollment_id,
        'course_changed',true,
        'previous_course_id',olde.course_id
      )
    );
  end if;

  perform public.ensure_free_registration_form_internal(p_enrollment_id);

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'student_enrollment_full_update','enrollment',p_enrollment_id,jsonb_build_object('before',to_jsonb(olde),'patch',p_patch));

  select to_jsonb(x) into v_out
  from (
    select e.*,c.name as course_name,c.type::text as course_type,cl.secretary_label as class_label
    from public.enrollments e
    join public.courses c on c.id=e.course_id
    left join public.classes cl on cl.id=e.class_id
    where e.id=p_enrollment_id
  ) x;

  return v_out;
end
$function$
;

CREATE OR REPLACE FUNCTION public.admin_student_update_profile(p_lead_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  oldrow jsonb;
  v public.leads%rowtype;
  phone text;
  bd date;
  calc_age integer;
  enr record;
begin
  if not public.is_master_admin() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  select to_jsonb(l) into oldrow
  from public.leads l
  where l.id=p_lead_id and l.deleted_at is null
  for update;

  if oldrow is null then raise exception 'student_not_found' using errcode='P0002'; end if;

  if p_patch ? 'full_name' and nullif(trim(p_patch->>'full_name'),'') is null then
    raise exception 'full_name_required' using errcode='22023';
  end if;

  if p_patch ? 'whatsapp' then
    phone:=regexp_replace(coalesce(p_patch->>'whatsapp',''),'\D','','g');
    if length(phone) in (10,11) then phone:='55'||phone; end if;
    if length(phone)<12 or length(phone)>13 then
      raise exception 'invalid_whatsapp' using errcode='22023';
    end if;
  end if;

  if p_patch ? 'birth_date' and nullif(p_patch->>'birth_date','') is not null then
    bd:=(p_patch->>'birth_date')::date;
    calc_age:=date_part('year',age(current_date,bd))::int;
    if calc_age<0 or calc_age>120 then raise exception 'invalid_birth_date' using errcode='22023'; end if;
  end if;

  if p_patch ? 'lead_score' and (p_patch->>'lead_score')::int not between 0 and 100 then
    raise exception 'invalid_lead_score' using errcode='22023';
  end if;

  update public.leads l set
    full_name=case when p_patch ? 'full_name' then trim(p_patch->>'full_name') else l.full_name end,
    whatsapp=case when p_patch ? 'whatsapp' then phone else l.whatsapp end,
    email=case when p_patch ? 'email' then nullif(trim(p_patch->>'email'),'') else l.email end,
    birth_date=case when p_patch ? 'birth_date' then nullif(p_patch->>'birth_date','')::date else l.birth_date end,
    age=case
      when p_patch ? 'age' then nullif(p_patch->>'age','')::int
      when p_patch ? 'birth_date' then calc_age
      else l.age
    end,
    address=case when p_patch ? 'address' then nullif(trim(p_patch->>'address'),'') else l.address end,
    neighborhood=case when p_patch ? 'neighborhood' then nullif(trim(p_patch->>'neighborhood'),'') else l.neighborhood end,
    zip_code=case when p_patch ? 'zip_code' then nullif(regexp_replace(coalesce(p_patch->>'zip_code',''),'\D','','g'),'') else l.zip_code end,
    guardian_name=case when p_patch ? 'guardian_name' then nullif(trim(p_patch->>'guardian_name'),'') else l.guardian_name end,
    guardian_whatsapp=case when p_patch ? 'guardian_whatsapp' then nullif(regexp_replace(coalesce(p_patch->>'guardian_whatsapp',''),'\D','','g'),'') else l.guardian_whatsapp end,
    guardian_birth_date=case when p_patch ? 'guardian_birth_date' then nullif(p_patch->>'guardian_birth_date','')::date else l.guardian_birth_date end,
    guardian_rg=case when p_patch ? 'guardian_rg' then nullif(trim(p_patch->>'guardian_rg'),'') else l.guardian_rg end,
    guardian_cpf=case when p_patch ? 'guardian_cpf' then nullif(regexp_replace(coalesce(p_patch->>'guardian_cpf',''),'\D','','g'),'') else l.guardian_cpf end,
    rg=case when p_patch ? 'rg' then nullif(trim(p_patch->>'rg'),'') else l.rg end,
    cpf=case when p_patch ? 'cpf' then nullif(regexp_replace(coalesce(p_patch->>'cpf',''),'\D','','g'),'') else l.cpf end,
    currently_working=case when p_patch ? 'currently_working' then nullif(p_patch->>'currently_working','')::boolean else l.currently_working end,
    currently_studying=case when p_patch ? 'currently_studying' then nullif(p_patch->>'currently_studying','')::boolean else l.currently_studying end,
    professional_goal=case when p_patch ? 'professional_goal' then nullif(trim(p_patch->>'professional_goal'),'') else l.professional_goal end,
    lead_score=case when p_patch ? 'lead_score' then (p_patch->>'lead_score')::int else l.lead_score end,
    status=case when p_patch ? 'status' then (p_patch->>'status')::public.lead_status else l.status end,
    archived=case when p_patch ? 'archived' then coalesce((p_patch->>'archived')::boolean,false) else l.archived end,
    source=case when p_patch ? 'source' then nullif(trim(p_patch->>'source'),'') else l.source end,
    campaign_code=case when p_patch ? 'campaign_code' then nullif(trim(p_patch->>'campaign_code'),'') else l.campaign_code end,
    landing_page=case when p_patch ? 'landing_page' then nullif(trim(p_patch->>'landing_page'),'') else l.landing_page end,
    referrer=case when p_patch ? 'referrer' then nullif(trim(p_patch->>'referrer'),'') else l.referrer end,
    utm_source=case when p_patch ? 'utm_source' then nullif(trim(p_patch->>'utm_source'),'') else l.utm_source end,
    utm_medium=case when p_patch ? 'utm_medium' then nullif(trim(p_patch->>'utm_medium'),'') else l.utm_medium end,
    utm_campaign=case when p_patch ? 'utm_campaign' then nullif(trim(p_patch->>'utm_campaign'),'') else l.utm_campaign end,
    utm_content=case when p_patch ? 'utm_content' then nullif(trim(p_patch->>'utm_content'),'') else l.utm_content end,
    updated_at=now()
  where l.id=p_lead_id
  returning l.* into v;

  update public.young_apprentice_registration_forms f
  set data_snapshot =
      f.data_snapshot
      || jsonb_build_object(
        'student_name',v.full_name,
        'age',v.age,
        'birth_date',v.birth_date,
        'whatsapp',v.whatsapp,
        'rg',v.rg,
        'cpf',v.cpf,
        'address',v.address,
        'neighborhood',v.neighborhood,
        'zip_code',v.zip_code,
        'guardian_name',v.guardian_name,
        'guardian_whatsapp',v.guardian_whatsapp,
        'guardian_birth_date',v.guardian_birth_date,
        'guardian_rg',v.guardian_rg,
        'guardian_cpf',v.guardian_cpf,
        'currently_studying',v.currently_studying
      )
      || case when p_patch ? 'school_status'
              then jsonb_build_object('school_status',nullif(trim(p_patch->>'school_status'),''))
              else '{}'::jsonb end
      || case when p_patch ? 'available_shift'
              then jsonb_build_object('available_shift',nullif(trim(p_patch->>'available_shift'),''))
              else '{}'::jsonb end,
      updated_at=now()
  where f.lead_id=p_lead_id;

  for enr in
    select e.id from public.enrollments e where e.lead_id=p_lead_id and e.cancelled_at is null
  loop
    perform public.ensure_free_registration_form_internal(enr.id);
  end loop;

  insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'student_full_profile_update','lead',p_lead_id,jsonb_build_object('before',oldrow,'patch',p_patch));

  return to_jsonb(v);
end
$function$
;

CREATE OR REPLACE FUNCTION public.ensure_free_registration_form_internal(p_enrollment_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lead uuid;
  v_course uuid;
  v_type public.course_type;
  v_id uuid;
  v_snapshot jsonb;
begin
  select e.lead_id,e.course_id,c.type
    into v_lead,v_course,v_type
  from public.enrollments e
  join public.courses c on c.id=e.course_id
  where e.id=p_enrollment_id and e.cancelled_at is null;

  if v_lead is null then
    delete from public.free_registration_forms where enrollment_id=p_enrollment_id;
    return null;
  end if;

  if v_type<>'gratuito' then
    delete from public.free_registration_forms where enrollment_id=p_enrollment_id;
    return null;
  end if;

  v_snapshot:=public.build_free_registration_snapshot(p_enrollment_id);

  insert into public.free_registration_forms(enrollment_id,lead_id,course_id,data_snapshot)
  values(p_enrollment_id,v_lead,v_course,coalesce(v_snapshot,'{}'::jsonb))
  on conflict(enrollment_id) do update
    set lead_id=excluded.lead_id,
        course_id=excluded.course_id,
        data_snapshot=excluded.data_snapshot,
        updated_at=now()
  returning id into v_id;

  return v_id;
end
$function$
;


revoke all on function public.ensure_free_registration_form_internal(uuid) from public,anon,authenticated;

revoke all on function public.admin_student_editor_get(uuid) from public,anon;
grant execute on function public.admin_student_editor_get(uuid) to authenticated;

revoke all on function public.admin_student_update_profile(uuid,jsonb) from public,anon;
grant execute on function public.admin_student_update_profile(uuid,jsonb) to authenticated;

revoke all on function public.admin_student_add_course(uuid,uuid,uuid,smallint,text) from public,anon;
grant execute on function public.admin_student_add_course(uuid,uuid,uuid,smallint,text) to authenticated;

revoke all on function public.admin_student_update_enrollment(uuid,jsonb) from public,anon;
grant execute on function public.admin_student_update_enrollment(uuid,jsonb) to authenticated;
