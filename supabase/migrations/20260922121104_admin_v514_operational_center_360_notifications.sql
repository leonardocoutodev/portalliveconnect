create table if not exists private.school_admin_notification_state(
  user_id uuid not null,
  notification_key text not null,
  read_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(user_id,notification_key)
);

revoke all on table private.school_admin_notification_state from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.admin_cancel_enrollment(p_enrollment_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lead uuid; oldrow jsonb;
begin
 if not public.school_has_permission('edit_students') then raise exception 'forbidden' using errcode='42501'; end if;
 select lead_id,to_jsonb(e) into v_lead,oldrow from public.enrollments e where id=p_enrollment_id for update;
 if v_lead is null then raise exception 'Matrícula não encontrada'; end if;
 update public.enrollments set cancelled_at=now(),cancelled_by=auth.uid(),cancellation_note=nullif(trim(p_reason),'') where id=p_enrollment_id;
 update public.leads set status='pre_inscricao',archived=false,updated_at=now() where id=v_lead and status='matricula_confirmada';
 insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'enrollment_cancel','enrollment',p_enrollment_id,jsonb_build_object('before',oldrow,'reason',p_reason));
end $function$;

CREATE OR REPLACE FUNCTION public.admin_restore_enrollment(p_enrollment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lead uuid;
begin
 if not public.school_has_permission('edit_students') then raise exception 'forbidden' using errcode='42501'; end if;
 select lead_id into v_lead from public.enrollments where id=p_enrollment_id;
 update public.enrollments set cancelled_at=null,cancelled_by=null,cancellation_note=null where id=p_enrollment_id;
 update public.leads set status='matricula_confirmada',archived=false,updated_at=now() where id=v_lead;
 insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'enrollment_restore','enrollment',p_enrollment_id,'{}'::jsonb);
end $function$;

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
  if not public.school_has_permission('edit_students') then
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
$function$;

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
  if not public.school_has_permission('edit_students') then
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
$function$;

CREATE OR REPLACE FUNCTION public.school_admin_global_search_v2(p_query text, p_limit integer DEFAULT 20)
 RETURNS TABLE(result_type text, action_kind text, view_name text, ref_id uuid, lead_id uuid, label text, subtitle text, rank_order integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_q text:=nullif(trim(coalesce(p_query,'')),'');
  v_digits text:=nullif(regexp_replace(trim(coalesce(p_query,'')),'\D','','g'),'');
  v_role text:=coalesce(public.current_user_role()::text,'');
  v_students boolean:=public.school_has_permission('view_students');
  v_finance boolean:=public.school_has_permission('view_finance');
  v_chat boolean:=public.school_has_permission('manage_chat');
begin
  if not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if v_q is null or char_length(v_q)<2 then return; end if;

  return query
  with hits as(
    select
      'Aluno'::text result_type,'student_360'::text action_kind,'sec-students'::text view_name,
      l.id ref_id,l.id lead_id,l.full_name label,
      concat_ws(' • ',nullif(l.whatsapp,''),nullif(l.email,''),nullif(l.cpf,'')) subtitle,
      10 rank_order,l.updated_at sort_at
    from public.leads l
    where v_students
      and l.deleted_at is null
      and (
        l.full_name ilike '%'||v_q||'%'
        or coalesce(l.email,'') ilike '%'||v_q||'%'
        or coalesce(l.rg,'') ilike '%'||v_q||'%'
        or (v_digits is not null and length(v_digits)>=3 and (
          regexp_replace(coalesce(l.whatsapp,''),'\D','','g') ilike '%'||v_digits||'%'
          or regexp_replace(coalesce(l.cpf,''),'\D','','g') ilike '%'||v_digits||'%'
        ))
        or exists(
          select 1 from public.enrollments e
          join public.courses c on c.id=e.course_id
          where e.lead_id=l.id and c.name ilike '%'||v_q||'%'
        )
      )

    union all
    select
      'Contrato','student_360','sec-students',ct.id,ct.lead_id,l.full_name,
      concat_ws(' • ',ct.contract_number,c.name,ct.status::text),
      20,ct.generated_at
    from public.contracts ct
    join public.leads l on l.id=ct.lead_id
    left join public.enrollments e on e.id=ct.enrollment_id
    left join public.courses c on c.id=e.course_id
    where v_students and (
      coalesce(ct.contract_number,'') ilike '%'||v_q||'%'
      or l.full_name ilike '%'||v_q||'%'
      or coalesce(c.name,'') ilike '%'||v_q||'%'
    )

    union all
    select
      'Ouro Moderno','student_360','sec-students',osl.id,osl.lead_id,coalesce(osl.student_name,l.full_name,'Aluno'),
      concat_ws(' • ','ID '||osl.ouro_student_id,nullif(osl.login,''),nullif(osl.email,'')),
      18,osl.updated_at
    from public.ouro_student_links osl
    left join public.leads l on l.id=osl.lead_id
    where v_students and osl.lead_id is not null and (
      osl.ouro_student_id ilike '%'||v_q||'%'
      or coalesce(osl.login,'') ilike '%'||v_q||'%'
      or coalesce(osl.student_name,'') ilike '%'||v_q||'%'
      or coalesce(osl.email,'') ilike '%'||v_q||'%'
      or (v_digits is not null and length(v_digits)>=3 and regexp_replace(coalesce(osl.phone,''),'\D','','g') ilike '%'||v_digits||'%')
    )

    union all
    select
      'Pagamento','finance','finance-control',p.id,e.lead_id,l.full_name,
      concat_ws(' • ',c.name,p.kind,p.status::text,'R$ '||p.amount::text),
      30,p.updated_at
    from public.payments p
    join public.enrollments e on e.id=p.enrollment_id
    join public.leads l on l.id=e.lead_id
    join public.courses c on c.id=e.course_id
    where v_finance and p.deleted_at is null and (
      l.full_name ilike '%'||v_q||'%'
      or c.name ilike '%'||v_q||'%'
      or coalesce(p.provider_payment_id,'') ilike '%'||v_q||'%'
      or p.id::text ilike '%'||v_q||'%'
    )

    union all
    select
      'Tarefa','chat_task','chat-internal',t.id,null,t.title,
      concat_ws(' • ',ap.full_name,case when t.due_at is not null then to_char(t.due_at at time zone 'America/Bahia','DD/MM HH24:MI') end,t.priority),
      40,t.updated_at
    from public.school_chat_tasks t
    left join public.profiles ap on ap.id=t.assigned_to
    where v_chat and (
      t.title ilike '%'||v_q||'%'
      or coalesce(t.description,'') ilike '%'||v_q||'%'
      or coalesce(ap.full_name,'') ilike '%'||v_q||'%'
    )

    union all
    select
      'Lead','lead','com-leads',l.id,l.id,l.full_name,
      concat_ws(' • ',l.whatsapp,l.email,replace(l.status::text,'_',' ')),
      25,l.updated_at
    from public.leads l
    where v_role in ('master_admin','coadmin','admin_comercial')
      and l.deleted_at is null
      and not v_students
      and (
        l.full_name ilike '%'||v_q||'%'
        or coalesce(l.email,'') ilike '%'||v_q||'%'
        or (v_digits is not null and length(v_digits)>=3 and regexp_replace(coalesce(l.whatsapp,''),'\D','','g') ilike '%'||v_digits||'%')
      )
  ),
  dedup as(
    select h.*,row_number() over(partition by h.result_type,h.ref_id order by h.rank_order,h.sort_at desc) rn
    from hits h
  )
  select d.result_type,d.action_kind,d.view_name,d.ref_id,d.lead_id,d.label,d.subtitle,d.rank_order
  from dedup d
  where d.rn=1
  order by d.rank_order,d.sort_at desc nulls last
  limit greatest(1,least(coalesce(p_limit,20),50));
end
$function$;

CREATE OR REPLACE FUNCTION public.school_admin_notification_mark_all_read()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  r record;
  v_count integer:=0;
begin
  if auth.uid() is null or not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  for r in select n.notification_key from public.school_admin_notifications(200,true) n loop
    insert into private.school_admin_notification_state(user_id,notification_key,read_at,updated_at)
    values(auth.uid(),r.notification_key,now(),now())
    on conflict(user_id,notification_key) do update set read_at=excluded.read_at,updated_at=now();
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('ok',true,'count',v_count);
end
$function$;

CREATE OR REPLACE FUNCTION public.school_admin_notification_mark_read(p_notification_key text, p_read boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
begin
  if auth.uid() is null or not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if nullif(trim(coalesce(p_notification_key,'')),'') is null then
    raise exception 'notification_key_required' using errcode='22023';
  end if;

  insert into private.school_admin_notification_state(user_id,notification_key,read_at,updated_at)
  values(auth.uid(),trim(p_notification_key),case when p_read then now() else null end,now())
  on conflict(user_id,notification_key) do update
  set read_at=excluded.read_at,updated_at=now();

  return jsonb_build_object('ok',true,'read',p_read);
end
$function$;

CREATE OR REPLACE FUNCTION public.school_admin_notifications(p_limit integer DEFAULT 50, p_include_read boolean DEFAULT false)
 RETURNS TABLE(notification_key text, category text, severity text, title text, subtitle text, action_view text, action_kind text, ref_id uuid, lead_id uuid, occurred_at timestamp with time zone, due_at timestamp with time zone, is_read boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_students boolean:=public.school_has_permission('view_students');
  v_finance boolean:=public.school_has_permission('view_finance');
  v_chat boolean:=public.school_has_permission('manage_chat');
  v_integrations boolean:=public.school_has_permission('manage_integrations');
  v_role text:=coalesce(public.current_user_role()::text,'');
begin
  if v_uid is null or not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  return query
  with items as(
    select
      'task:'||t.id::text as notification_key,
      'Tarefa'::text category,
      case when t.due_at<now() or t.priority='urgente' then 'danger'
           when t.priority='alta' or t.due_at<=now()+interval '24 hours' then 'warning'
           else 'info' end severity,
      case when t.due_at<now() then 'Tarefa atrasada' else 'Tarefa pendente' end title,
      concat_ws(' • ',t.title,
        case when t.due_at is not null then 'Prazo '||to_char(t.due_at at time zone 'America/Bahia','DD/MM HH24:MI') end,
        'Prioridade '||t.priority) subtitle,
      'chat-internal'::text action_view,'chat_task'::text action_kind,t.id ref_id,null::uuid lead_id,
      greatest(t.updated_at,coalesce(t.last_reminded_at,t.created_at)) occurred_at,t.due_at
    from public.school_chat_tasks t
    where v_chat and t.status='pendente' and t.assigned_to=v_uid

    union all
    select
      'portal:'||q.id::text,
      'Matrícula',
      case when q.payment_approved_at is not null then 'danger' else 'warning' end,
      case when q.payment_approved_at is not null then 'Matrícula paga aguardando ação' else 'Matrícula do portal aguardando ação' end,
      concat_ws(' • ',l.full_name,c.name,replace(q.status,'_',' ')),
      'sec-portal','student_360',q.id,q.lead_id,q.updated_at,null::timestamptz
    from public.portal_enrollment_queue q
    join public.leads l on l.id=q.lead_id
    left join public.courses c on c.id=q.course_id
    where v_students and q.status not in ('matriculada_ouro','matriculada_manual','cancelada')

    union all
    select
      'ouro-error:'||q.id::text,
      'Ouro Moderno','danger','Falha no provisionamento EAD',
      concat_ws(' • ',l.full_name,c.name,coalesce(q.ouro_last_error,'erro desconhecido')),
      'sec-ouro','student_360',q.id,q.lead_id,coalesce(q.ouro_last_attempt_at,q.updated_at),null::timestamptz
    from public.portal_enrollment_queue q
    join public.leads l on l.id=q.lead_id
    left join public.courses c on c.id=q.course_id
    where (v_students or v_integrations)
      and q.ouro_last_error is not null
      and q.status not in ('matriculada_ouro','matriculada_manual','cancelada')

    union all
    select
      'payment:'||p.id::text,
      'Financeiro',
      case when p.due_date<current_date then 'danger' else 'warning' end,
      case when p.due_date<current_date then 'Pagamento vencido' else 'Pagamento próximo do vencimento' end,
      concat_ws(' • ',l.full_name,c.name,p.kind,'R$ '||p.amount::text),
      'finance-control','student_360',p.id,e.lead_id,p.updated_at,p.due_date::timestamptz
    from public.payments p
    join public.enrollments e on e.id=p.enrollment_id
    join public.leads l on l.id=e.lead_id
    join public.courses c on c.id=e.course_id
    where v_finance and p.deleted_at is null and p.status::text='pendente'
      and p.due_date is not null and p.due_date<=current_date+7

    union all
    select
      'contract:'||ct.id::text,
      'Contrato',
      case when ct.generated_at<now()-interval '3 days' then 'warning' else 'info' end,
      'Contrato aguardando assinatura',
      concat_ws(' • ',l.full_name,c.name,ct.contract_number),
      'sec-contracts','student_360',ct.id,ct.lead_id,coalesce(ct.printed_at,ct.generated_at),null::timestamptz
    from public.contracts ct
    join public.leads l on l.id=ct.lead_id
    left join public.enrollments e on e.id=ct.enrollment_id
    left join public.courses c on c.id=e.course_id
    where v_students and ct.archived_at is null and ct.status::text<>'assinado'

    union all
    select
      'followup:'||f.id::text,
      'Comercial',
      case when f.scheduled_at<now() then 'warning' else 'info' end,
      case when f.scheduled_at<now() then 'Follow-up atrasado' else 'Follow-up agendado' end,
      concat_ws(' • ',l.full_name,f.note),
      'com-followups','lead',f.id,f.lead_id,coalesce(f.scheduled_at,f.created_at),f.scheduled_at
    from public.followups f
    join public.leads l on l.id=f.lead_id
    where v_role in ('master_admin','coadmin','admin_comercial')
      and f.status='pendente'
      and f.scheduled_at is not null
      and f.scheduled_at<=now()+interval '24 hours'

    union all
    select
      'chat:'||c.channel_id::text,
      'Chat',
      case when c.unread_count>=5 then 'warning' else 'info' end,
      'Mensagens não lidas',
      concat_ws(' • ',coalesce(c.counterpart_name,c.participant_a_name,'Conversa'),c.unread_count::text||' não lida(s)',c.last_message),
      'chat-internal','chat',c.channel_id,null::uuid,c.last_message_at,null::timestamptz
    from public.school_chat_conversations_v2() c
    where v_chat and c.unread_count>0
  ),
  marked as(
    select
      i.*,
      (s.read_at is not null and s.read_at>=i.occurred_at) as is_read
    from items i
    left join private.school_admin_notification_state s
      on s.user_id=v_uid and s.notification_key=i.notification_key
  )
  select
    m.notification_key,m.category,m.severity,m.title,m.subtitle,m.action_view,m.action_kind,
    m.ref_id,m.lead_id,m.occurred_at,m.due_at,m.is_read
  from marked m
  where p_include_read or not m.is_read
  order by
    case m.severity when 'danger' then 1 when 'warning' then 2 else 3 end,
    m.due_at nulls last,
    m.occurred_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
end
$function$;

CREATE OR REPLACE FUNCTION public.school_admin_operational_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_students boolean:=public.school_has_permission('view_students');
  v_finance boolean:=public.school_has_permission('view_finance');
  v_chat boolean:=public.school_has_permission('manage_chat');
  v_role text:=coalesce(public.current_user_role()::text,'');
  v_unread bigint:=0;
begin
  if auth.uid() is null or not public.is_staff() then
    raise exception 'forbidden' using errcode='42501';
  end if;

  if v_chat then
    select coalesce(sum(c.unread_count),0) into v_unread
    from public.school_chat_conversations_v2() c;
  end if;

  return jsonb_build_object(
    'generated_at',now(),
    'capabilities',jsonb_build_object(
      'students',v_students,'finance',v_finance,'chat',v_chat,
      'commercial',v_role in ('master_admin','coadmin','admin_comercial')
    ),
    'counts',jsonb_build_object(
      'active_students',case when v_students then (
        select count(distinct e.lead_id) from public.enrollments e where e.cancelled_at is null
      ) else 0 end,
      'active_enrollments',case when v_students then (
        select count(*) from public.enrollments e where e.cancelled_at is null
      ) else 0 end,
      'classes_open',case when v_students then (
        select count(*) from public.classes c where c.status::text='aberta' and coalesce(c.source_hidden,false)=false
      ) else 0 end,
      'classes_full',case when v_students then (
        select count(*) from public.classes c where c.status::text='lotada'
      ) else 0 end,
      'portal_waiting',case when v_students then (
        select count(*) from public.portal_enrollment_queue q
        where q.status not in ('matriculada_ouro','matriculada_manual','cancelada')
      ) else 0 end,
      'ouro_failures',case when v_students then (
        select count(*) from public.portal_enrollment_queue q
        where q.ouro_last_error is not null
          and q.status not in ('matriculada_ouro','matriculada_manual','cancelada')
      ) else 0 end,
      'pending_contracts',case when v_students then (
        select count(*) from public.contracts ct
        where ct.archived_at is null and ct.status::text<>'assinado'
      ) else 0 end,
      'overdue_payments',case when v_finance then (
        select count(*) from public.payments p
        where p.deleted_at is null and p.status::text='pendente'
          and p.due_date is not null and p.due_date<current_date
      ) else 0 end,
      'due_soon_payments',case when v_finance then (
        select count(*) from public.payments p
        where p.deleted_at is null and p.status::text='pendente'
          and p.due_date between current_date and current_date+7
      ) else 0 end,
      'pending_tasks',case when v_chat then (
        select count(*) from public.school_chat_tasks t
        where t.status='pendente' and t.assigned_to=auth.uid()
      ) else 0 end,
      'overdue_tasks',case when v_chat then (
        select count(*) from public.school_chat_tasks t
        where t.status='pendente' and t.assigned_to=auth.uid()
          and t.due_at is not null and t.due_at<now()
      ) else 0 end,
      'unread_chat',v_unread,
      'followups_due',case when v_role in ('master_admin','coadmin','admin_comercial') then (
        select count(*) from public.followups f
        where f.status='pendente' and f.scheduled_at is not null and f.scheduled_at<=now()
      ) else 0 end,
      'new_leads_today',case when v_role in ('master_admin','coadmin','admin_comercial') then (
        select count(*) from public.leads l
        where l.deleted_at is null and l.created_at::date=current_date
      ) else 0 end
    )
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.school_student_360(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'extensions', 'vault'
AS $function$
declare
  v_lead jsonb;
  v_enrollments jsonb;
  v_courses jsonb;
  v_classes jsonb;
  v_young jsonb;
  v_payments jsonb:='[]'::jsonb;
  v_contracts jsonb;
  v_ouro jsonb;
  v_portal jsonb;
  v_credentials jsonb;
  v_timeline jsonb;
  v_alerts jsonb;
  v_finance boolean:=public.school_has_permission('view_finance');
begin
  if not public.school_has_permission('view_students') then
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
     or exists(select 1 from public.enrollments e where e.lead_id=p_lead_id and e.course_id=c.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',cl.id,'course_id',cl.course_id,'label',cl.secretary_label,'weekday',cl.weekday,
    'start_time',cl.start_time,'end_time',cl.end_time,'start_date',cl.start_date,
    'status',cl.status::text,'capacity',cl.capacity,'room_name',cl.room_name,'source_hidden',cl.source_hidden
  ) order by cl.weekday,cl.start_time),'[]'::jsonb)
  into v_classes
  from public.classes cl
  where (cl.status in ('aberta','lotada') and coalesce(cl.source_hidden,false)=false)
     or exists(select 1 from public.enrollments e where e.lead_id=p_lead_id and e.class_id=cl.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'form_id',f.id,'status',f.status,'data_snapshot',f.data_snapshot,
    'generated_at',f.generated_at,'printed_at',f.printed_at
  ) order by f.generated_at desc),'[]'::jsonb)
  into v_young
  from public.young_apprentice_registration_forms f
  where f.lead_id=p_lead_id;

  if v_finance then
    select coalesce(jsonb_agg(jsonb_build_object(
      'payment_id',p.id,'enrollment_id',p.enrollment_id,'course_name',c.name,'kind',p.kind,
      'amount',p.amount,'method',p.method::text,'status',p.status::text,'due_date',p.due_date,
      'paid_at',p.paid_at,'provider',p.provider,'provider_payment_id',p.provider_payment_id,
      'admin_note',p.admin_note,'created_at',p.created_at,'updated_at',p.updated_at
    ) order by coalesce(p.due_date,p.created_at::date) desc,p.created_at desc),'[]'::jsonb)
    into v_payments
    from public.payments p
    join public.enrollments e on e.id=p.enrollment_id
    join public.courses c on c.id=e.course_id
    where e.lead_id=p_lead_id and p.deleted_at is null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'contract_id',ct.id,'enrollment_id',ct.enrollment_id,'contract_number',ct.contract_number,
    'course_name',c.name,'status',ct.status::text,'generated_at',ct.generated_at,
    'printed_at',ct.printed_at,'signed_at',ct.signed_at,'archived_at',ct.archived_at
  ) order by ct.generated_at desc),'[]'::jsonb)
  into v_contracts
  from public.contracts ct
  left join public.enrollments e on e.id=ct.enrollment_id
  left join public.courses c on c.id=e.course_id
  where ct.lead_id=p_lead_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,'ouro_student_id',o.ouro_student_id,'login',o.login,'student_name',o.student_name,
    'email',o.email,'phone',o.phone,'last_event_name',o.last_event_name,
    'last_event_at',o.last_event_at,'last_login_at',o.last_login_at,'updated_at',o.updated_at
  ) order by o.updated_at desc),'[]'::jsonb)
  into v_ouro
  from public.ouro_student_links o
  where o.lead_id=p_lead_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'queue_id',q.id,'course_id',q.course_id,'course_name',c.name,'status',q.status,
    'created_at',q.created_at,'updated_at',q.updated_at,'payment_approved_at',q.payment_approved_at,
    'completed_at',q.completed_at,'ouro_student_id',q.ouro_student_id,
    'ouro_attempt_count',q.ouro_attempt_count,'ouro_last_attempt_at',q.ouro_last_attempt_at,
    'ouro_last_error',q.ouro_last_error,'ouro_created_student',q.ouro_created_student
  ) order by q.created_at desc),'[]'::jsonb)
  into v_portal
  from public.portal_enrollment_queue q
  left join public.courses c on c.id=q.course_id
  where q.lead_id=p_lead_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'queue_id',pac.queue_id,'ouro_student_id',pac.ouro_student_id,'username',pac.username,
    'password_available',pac.password_cipher is not null,
    'email_status',pac.email_status,'email_sent_at',pac.email_sent_at,
    'whatsapp_prepared_at',pac.whatsapp_prepared_at,'whatsapp_sent_at',pac.whatsapp_sent_at,
    'created_at',pac.created_at,'updated_at',pac.updated_at
  ) order by pac.updated_at desc),'[]'::jsonb)
  into v_credentials
  from private.portal_access_credentials pac
  join public.portal_enrollment_queue q on q.id=pac.queue_id
  where q.lead_id=p_lead_id;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.event_at desc),'[]'::jsonb)
  into v_timeline
  from (
    select 'lead_created'::text event_type,'Cadastro criado'::text label,l.created_at event_at,null::text detail,null::uuid ref_id
    from public.leads l where l.id=p_lead_id
    union all
    select 'enrollment','Matrícula: '||c.name,e.enrolled_at,
      case when e.cancelled_at is null then 'Ativa' else 'Encerrada' end,e.id
    from public.enrollments e join public.courses c on c.id=e.course_id where e.lead_id=p_lead_id
    union all
    select 'payment','Pagamento: '||c.name,p.created_at,
      p.kind||' • '||p.status::text||' • R$ '||p.amount::text,p.id
    from public.payments p join public.enrollments e on e.id=p.enrollment_id
    join public.courses c on c.id=e.course_id
    where e.lead_id=p_lead_id and p.deleted_at is null
    union all
    select 'contract','Contrato '||ct.contract_number,ct.generated_at,ct.status::text,ct.id
    from public.contracts ct where ct.lead_id=p_lead_id
    union all
    select 'portal','Portal / Ouro: '||coalesce(c.name,'Curso'),q.updated_at,
      concat_ws(' • ',replace(q.status,'_',' '),q.ouro_last_error),q.id
    from public.portal_enrollment_queue q left join public.courses c on c.id=q.course_id
    where q.lead_id=p_lead_id
    union all
    select 'ouro','Ouro Moderno',coalesce(o.last_event_at,o.updated_at),
      concat_ws(' • ',o.last_event_name,'ID '||o.ouro_student_id),o.id
    from public.ouro_student_links o where o.lead_id=p_lead_id
  ) t;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into v_alerts
  from (
    select jsonb_build_object('severity','danger','type','finance','label','Pagamento vencido','count',count(*)) x
    from public.payments p join public.enrollments e on e.id=p.enrollment_id
    where v_finance and e.lead_id=p_lead_id and p.deleted_at is null and p.status::text='pendente'
      and p.due_date is not null and p.due_date<current_date
    having count(*)>0
    union all
    select jsonb_build_object('severity','warning','type','contract','label','Contrato aguardando assinatura','count',count(*))
    from public.contracts ct
    where ct.lead_id=p_lead_id and ct.archived_at is null and ct.status::text<>'assinado'
    having count(*)>0
    union all
    select jsonb_build_object('severity','danger','type','ouro','label','Falha de integração com Ouro','count',count(*))
    from public.portal_enrollment_queue q
    where q.lead_id=p_lead_id and q.ouro_last_error is not null
      and q.status not in ('matriculada_ouro','matriculada_manual','cancelada')
    having count(*)>0
  ) a;

  return jsonb_build_object(
    'lead',v_lead,
    'enrollments',v_enrollments,
    'courses',v_courses,
    'classes',v_classes,
    'young_apprentice_forms',v_young,
    'payments',v_payments,
    'contracts',v_contracts,
    'ouro_links',v_ouro,
    'portal_queue',v_portal,
    'credentials',v_credentials,
    'timeline',v_timeline,
    'alerts',v_alerts,
    'capabilities',jsonb_build_object(
      'view_finance',v_finance,
      'edit_students',public.school_has_permission('edit_students')
    )
  );
end
$function$;


revoke all on function public.school_admin_global_search_v2(text,integer) from public,anon;
grant execute on function public.school_admin_global_search_v2(text,integer) to authenticated,service_role;

revoke all on function public.school_admin_notifications(integer,boolean) from public,anon;
grant execute on function public.school_admin_notifications(integer,boolean) to authenticated,service_role;

revoke all on function public.school_admin_notification_mark_read(text,boolean) from public,anon;
grant execute on function public.school_admin_notification_mark_read(text,boolean) to authenticated,service_role;

revoke all on function public.school_admin_notification_mark_all_read() from public,anon;
grant execute on function public.school_admin_notification_mark_all_read() to authenticated,service_role;

revoke all on function public.school_admin_operational_dashboard() from public,anon;
grant execute on function public.school_admin_operational_dashboard() to authenticated,service_role;

revoke all on function public.school_student_360(uuid) from public,anon;
grant execute on function public.school_student_360(uuid) to authenticated,service_role;
