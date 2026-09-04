
create or replace function public.lico_valid_name(p_name text)
returns boolean language sql immutable set search_path='pg_catalog','public' as $$
  select
    length(trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g'))) between 5 and 140
    and trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g')) like '% %'
    and trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g')) ~ '^[[:alpha:]À-ÿ'' -]+$'
    and lower(trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g'))) not in
      ('nome sobrenome','seu nome','sem nome','nao sei','não sei','teste teste','cliente cliente',
       'visitante visitante','fulano de tal','asdf asdf','aaaa aaaa','meu nome')
$$;

create or replace function public.lico_slugify(p_text text)
returns text language sql immutable set search_path='pg_catalog','public' as $$
  select trim(both '-' from regexp_replace(
    lower(translate(coalesce(p_text,''),
      'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ',
      'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC')),
    '[^a-z0-9]+','-','g'))
$$;

create or replace function private.lico_append(
  p_session_id uuid,p_sender_type text,p_body text,p_metadata jsonb default '{}'::jsonb
) returns uuid language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare v_id uuid;
begin
  insert into public.commercial_chat_messages(session_id,sender_type,body,metadata)
  values(p_session_id,p_sender_type,trim(p_body),coalesce(p_metadata,'{}'::jsonb))
  returning id into v_id;
  update public.commercial_chat_sessions
  set last_message_at=now(),updated_at=now()
  where id=p_session_id;
  return v_id;
end $$;

create or replace function private.lico_sync_lead(p_session_id uuid)
returns uuid language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare s public.commercial_chat_sessions%rowtype; v_lead uuid; v_phone text; v_student_name text; v_student_age int;
begin
  select * into s from public.commercial_chat_sessions where id=p_session_id;
  if s.id is null or nullif(trim(s.full_name),'') is null or nullif(trim(s.whatsapp),'') is null then return null; end if;
  v_phone:=regexp_replace(s.whatsapp,'\D','','g');
  if length(v_phone) in (10,11) then v_phone:='55'||v_phone; end if;
  v_student_name:=coalesce(nullif(trim(s.student_name),''),s.full_name);
  v_student_age:=coalesce(s.student_age,s.age);

  select l.id into v_lead
  from public.leads l
  where l.deleted_at is null
    and (
      regexp_replace(coalesce(l.whatsapp,''),'\D','','g') in (v_phone, regexp_replace(v_phone,'^55','',''))
      or regexp_replace(coalesce(l.whatsapp_normalized,''),'\D','','g') in (v_phone, regexp_replace(v_phone,'^55','',''))
    )
  order by l.updated_at desc nulls last
  limit 1;

  if v_lead is null then
    insert into public.leads(
      full_name,whatsapp,age,email,professional_goal,currently_working,currently_studying,
      guardian_name,guardian_whatsapp,source,status,lead_score,landing_page,referrer,
      utm_source,utm_medium,utm_campaign,utm_content
    ) values(
      v_student_name,v_phone,v_student_age,s.email,s.objective,s.works,s.studies,
      case when coalesce(v_student_age,99)<18 then s.full_name else null end,
      case when coalesce(v_student_age,99)<18 then v_phone else null end,
      'portal_chatbot','pre_inscricao',greatest(coalesce(s.lead_score,0),35),
      s.landing_page,s.referrer,s.utm_source,s.utm_medium,s.utm_campaign,s.utm_content
    ) returning id into v_lead;
  else
    update public.leads l set
      full_name=coalesce(v_student_name,l.full_name),
      whatsapp=coalesce(v_phone,l.whatsapp),
      age=coalesce(v_student_age,l.age),
      email=coalesce(nullif(s.email,''),l.email),
      professional_goal=coalesce(nullif(s.objective,''),l.professional_goal),
      currently_working=coalesce(s.works,l.currently_working),
      currently_studying=coalesce(s.studies,l.currently_studying),
      guardian_name=case when coalesce(v_student_age,99)<18 then coalesce(s.full_name,l.guardian_name) else l.guardian_name end,
      guardian_whatsapp=case when coalesce(v_student_age,99)<18 then coalesce(v_phone,l.guardian_whatsapp) else l.guardian_whatsapp end,
      lead_score=greatest(coalesce(l.lead_score,0),coalesce(s.lead_score,0)),
      landing_page=coalesce(s.landing_page,l.landing_page),
      referrer=coalesce(s.referrer,l.referrer),
      utm_source=coalesce(s.utm_source,l.utm_source),
      utm_medium=coalesce(s.utm_medium,l.utm_medium),
      utm_campaign=coalesce(s.utm_campaign,l.utm_campaign),
      utm_content=coalesce(s.utm_content,l.utm_content),
      updated_at=now()
    where l.id=v_lead;
  end if;

  update public.commercial_chat_sessions set lead_id=v_lead where id=p_session_id and lead_id is distinct from v_lead;
  return v_lead;
end $$;

create or replace function private.lico_objective_prompt(p_session_id uuid)
returns text language plpgsql stable security definer
set search_path='pg_catalog','public','private' as $$
declare s public.commercial_chat_sessions%rowtype; a int;
begin
 select * into s from public.commercial_chat_sessions where id=p_session_id;
 a:=coalesce(s.student_age,s.age,0);
 if a<14 then
   return 'Pensando nessa idade, qual é o objetivo principal: desenvolver informática/tecnologia, criatividade, inglês, aprender algo novo ou se preparar desde cedo para o futuro?';
 elsif a<=18 and not coalesce(s.works,false) and not coalesce(s.ever_worked,false) then
   return 'Como ainda está no início da vida profissional, qual é o principal objetivo: conseguir o primeiro emprego, preparar o currículo, descobrir uma área profissional, aprender uma habilidade específica ou se destacar para o Jovem Aprendiz?';
 elsif a<=18 then
   return 'Qual é o principal objetivo agora: conseguir uma oportunidade melhor, preparar o currículo, aprender uma habilidade específica, descobrir uma área profissional ou mudar de área com base na experiência que já teve?';
 elsif coalesce(s.works,false) then
   return 'Qual é o objetivo profissional principal: crescer na área atual, conseguir emprego melhor, mudar de área, aumentar a renda, empreender ou aprender uma habilidade específica?';
 elsif coalesce(s.ever_worked,false) then
   return 'Qual é o objetivo principal: voltar ao mercado, conseguir emprego melhor, mudar de área, atualizar o currículo, empreender ou aprender uma habilidade específica?';
 else
   return 'Qual é o objetivo principal: conseguir o primeiro emprego, construir um currículo mais forte, aprender uma profissão, empreender ou desenvolver uma habilidade específica?';
 end if;
end $$;

create or replace function private.lico_recommend_courses(p_session_id uuid)
returns text language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare s public.commercial_chat_sessions%rowtype; v_json jsonb; v_text text;
begin
  select * into s from public.commercial_chat_sessions where id=p_session_id;
  with scored as (
    select c.id,c.name,c.type::text as type,
      (
        case when coalesce(s.objective,'') ilike '%admin%' or coalesce(s.objective,'') ilike '%empresa%' or coalesce(s.objective,'') ilike '%escrit%' or coalesce(s.objective,'') ilike '%contab%' or coalesce(s.objective,'') ilike '%finance%' then
          case when c.name ilike any(array['%ADMIN%','%GESTÃO%','%ESCRIT%','%CONTÁB%','%FINANCE%']) then 8 else 0 end else 0 end
        + case when coalesce(s.objective,'') ilike '%informat%' or coalesce(s.objective,'') ilike '%tecnolog%' or coalesce(s.objective,'') ilike '%excel%' or coalesce(s.objective,'') ilike '%program%' then
          case when c.name ilike any(array['%INFORM%','%EXCEL%','%OFFICE%','%PROGRAM%','%APP%','%WEB%','%COMPUT%']) then 8 else 0 end else 0 end
        + case when coalesce(s.objective,'') ilike '%saúde%' or coalesce(s.objective,'') ilike '%saude%' or coalesce(s.objective,'') ilike '%farm%' then
          case when c.name ilike any(array['%SAÚDE%','%SAUDE%','%FARM%']) then 8 else 0 end else 0 end
        + case when coalesce(s.objective,'') ilike '%design%' or coalesce(s.objective,'') ilike '%marketing%' or coalesce(s.objective,'') ilike '%social%' then
          case when c.name ilike any(array['%DESIGN%','%SOCIAL%','%MARKETING%','%TRÁFEGO%','%TRAFEGO%','%YOUTUBER%']) then 8 else 0 end else 0 end
        + case when coalesce(s.objective,'') ilike '%ingl%' then case when c.name ilike '%INGL%' then 8 else 0 end else 0 end
        + case when coalesce(s.objective,'') ilike '%beleza%' then case when c.name ilike '%BELEZA%' then 8 else 0 end else 0 end
        + case when coalesce(s.student_age,s.age,99)<=13 and c.name ilike '%KIDS%' then 12
               when coalesce(s.student_age,s.age,99)>13 and c.name ilike '%KIDS%' then -12 else 0 end
        + case when exists(
            select 1 from public.class_capacity_summary cl
            where cl.course_id=c.id and cl.status='aberta' and coalesce(cl.source_hidden,false)=false and cl.remaining_seats>0
              and (
                s.availability_period in ('flexivel','ead') or s.availability_period is null
                or (s.availability_period='manha' and cl.start_time<'12:00'::time)
                or (s.availability_period='tarde' and cl.start_time>='12:00'::time and cl.start_time<'17:00'::time)
                or (s.availability_period='noite' and cl.weekday=3 and cl.start_time='18:00'::time)
              )
          ) then 10 else 0 end
        + case when c.featured then 1 else 0 end
      ) as score
    from public.courses c
    where c.active=true
      and (coalesce(s.student_age,s.age,99)<=13 or c.name not ilike '%KIDS%')
    order by score desc,c.featured desc,c.name
    limit 5
  ), numbered as (
    select *,row_number() over(order by score desc,name) as n from scored
  )
  select
    coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'type',type) order by n),'[]'::jsonb),
    coalesce(string_agg(n::text||'. '||name,E'\n' order by n),'')
  into v_json,v_text from numbered;

  update public.commercial_chat_sessions
  set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('suggested_courses',v_json),updated_at=now()
  where id=p_session_id;
  return v_text;
end $$;

create or replace function public.portal_lico_chat(
  p_action text,
  p_token uuid default null,
  p_message text default null,
  p_context jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private' as $$
declare
  s public.commercial_chat_sessions%rowtype;
  v_id uuid; v_msg text:=trim(coalesce(p_message,'')); n text:=lower(trim(coalesce(p_message,'')));
  v_out text; v_next text; v_score int; v_phone text; v_age int; v_bool boolean; v_rel text; v_shift text;
  v_period text; v_timeline text; v_factor text; v_courses text; v_idx int; v_course jsonb; v_course_id uuid;
  v_class record; v_lead uuid; v_offer text; v_link text; v_student_age int; v_need_authority boolean;
  v_attempts int; v_staff jsonb;
begin
  if p_action='start' then
    insert into public.commercial_chat_sessions(
      landing_page,referrer,utm_source,utm_medium,utm_campaign,utm_content,course_interest,metadata
    ) values(
      nullif(trim(p_context->>'landing_page'),''),
      nullif(trim(p_context->>'referrer'),''),
      nullif(trim(p_context->>'utm_source'),''),
      nullif(trim(p_context->>'utm_medium'),''),
      nullif(trim(p_context->>'utm_campaign'),''),
      nullif(trim(p_context->>'utm_content'),''),
      nullif(trim(p_context->>'course_name'),''),
      jsonb_build_object('course_slug',nullif(trim(p_context->>'course_slug'),''),'lico_version','5.8.0')
    ) returning id,public_token into v_id,p_token;
    v_out:='Olá! Eu sou o Lico, assistente da Live Connect. Vou entender seu perfil, indicar a formação mais adequada e acompanhar você até a matrícula. Para começar, preciso do seu nome e sobrenome.';
    perform private.lico_append(v_id,'assistant',v_out,jsonb_build_object('stage','name','assistant','Lico'));
    return jsonb_build_object('ok',true,'token',p_token,'session_id',v_id,'stage','name','message',v_out);
  end if;

  if p_token is null then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  select * into s from public.commercial_chat_sessions where public_token=p_token;
  if s.id is null then return jsonb_build_object('ok',false,'error','session_not_found'); end if;

  if p_action='poll' then
    select coalesce(jsonb_agg(x order by x->>'created_at'),'[]'::jsonb) into v_staff
    from (
      select jsonb_build_object('id',m.id,'body',m.body,'created_at',m.created_at) x
      from public.commercial_chat_messages m
      where m.session_id=s.id and m.sender_type='staff'
      order by m.created_at desc limit 40
    ) q;
    return jsonb_build_object('ok',true,'token',p_token,'status',s.status,
      'handoff',(s.assigned_to is not null or s.status='handoff'),'messages',coalesce(v_staff,'[]'::jsonb));
  elsif p_action='prefill' then
    return jsonb_build_object(
      'ok',true,'token',p_token,
      'student_name',coalesce(s.student_name,s.full_name),
      'contact_name',s.full_name,'whatsapp',s.whatsapp,'email',s.email,
      'student_age',coalesce(s.student_age,s.age),'relationship',s.relationship,
      'guardian_name',case when coalesce(s.student_age,s.age,99)<18 then s.full_name else null end,
      'preferred_class_id',s.preferred_class_id,'preferred_schedule',s.preferred_schedule,
      'course_interest',s.course_interest,
      'qualified',(s.qualification_completed_at is not null or s.lead_score>=90)
    );
  end if;

  if nullif(v_msg,'') is null then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  perform private.lico_append(s.id,'visitor',v_msg,'{}'::jsonb);

  if s.assigned_to is not null or s.status='handoff' then
    return jsonb_build_object('ok',true,'token',p_token,'stage','handoff','handoff',true,
      'message','Recebi sua mensagem. Um consultor da Live Connect continuará o atendimento por aqui.');
  end if;

  if n ~ '(humano|atendente|consultor|vendedor|falar com algu[eé]m|equipe)' then
    update public.commercial_chat_sessions set status='handoff',stage='handoff',updated_at=now() where id=s.id;
    v_out:='Perfeito. Vou chamar o Comercial da Live Connect. Você pode continuar escrevendo por aqui.';
    perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage','handoff','assistant','Lico'));
    return jsonb_build_object('ok',true,'token',p_token,'stage','handoff','handoff',true,'message',v_out);
  end if;

  if s.stage='name' then
    if not public.lico_valid_name(v_msg) then
      v_attempts:=coalesce((s.metadata->>'name_attempts')::int,0)+1;
      update public.commercial_chat_sessions
      set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('name_attempts',v_attempts),updated_at=now()
      where id=s.id;
      v_out:=case when v_attempts=1
        then 'Preciso do seu nome e sobrenome reais para registrar o atendimento. Por exemplo: “Maria Oliveira”. Qual é o seu nome completo?'
        else 'Ainda não consegui validar o nome. Para eu continuar, digite nome e sobrenome sem apelidos, números ou respostas genéricas.' end;
      perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage','name','validation','invalid_name','assistant','Lico'));
      return jsonb_build_object('ok',true,'token',p_token,'stage','name','message',v_out,'blocked',true);
    end if;
    update public.commercial_chat_sessions
    set full_name=trim(regexp_replace(v_msg,'\s+',' ','g')),stage='whatsapp',lead_score=12,updated_at=now()
    where id=s.id;
    v_out:='Obrigado, '||split_part(trim(v_msg),' ',1)||'. Agora me informe seu WhatsApp com DDD.';
    perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage','whatsapp','assistant','Lico'));
    return jsonb_build_object('ok',true,'token',p_token,'stage','whatsapp','message',v_out,'lead_score',12);
  end if;

  if n ~ '(pre[cç]o|valor|matr[ií]cula|mensalidade|quanto custa|investimento)' then
    select coalesce(c.offer_text,c.title) into v_offer
    from public.campaigns c
    where c.active=true and c.highlight_public=true
      and (c.start_date is null or c.start_date<=current_date)
      and (c.end_date is null or c.end_date>=current_date)
    order by c.priority desc,c.created_at desc limit 1;
    v_out:=coalesce(v_offer,'A condição depende da formação escolhida. Primeiro vou terminar sua qualificação para não te passar uma opção inadequada.');
    v_out:=v_out||E'\n\n'||case s.stage
      when 'whatsapp' then 'Agora me informe seu WhatsApp com DDD.'
      when 'contact_age' then 'Qual é a sua idade?'
      when 'relationship' then 'O curso é para você ou para outra pessoa?'
      else 'Vamos continuar de onde paramos para eu fechar seu perfil corretamente.' end;
    perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage',s.stage,'assistant','Lico','kind','pricing'));
    return jsonb_build_object('ok',true,'token',p_token,'stage',s.stage,'message',v_out);
  end if;

  if n ~ '(endere[cç]o|onde fica|localiza[cç][aã]o)' then
    v_out:='A Live Connect fica na Rua Sá Oliveira, 18, Ed. Empresarial Fraga Center, Sala 01, Centro, Ilhéus - BA. Vamos continuar sua qualificação.';
    perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage',s.stage,'assistant','Lico','kind','address'));
    return jsonb_build_object('ok',true,'token',p_token,'stage',s.stage,'message',v_out);
  end if;

  if s.stage='whatsapp' then
    v_phone:=regexp_replace(v_msg,'\D','','g');
    if length(v_phone) in (10,11) then v_phone:='55'||v_phone; end if;
    if length(v_phone) not in (12,13) then
      v_out:='Não consegui validar o número. Envie o WhatsApp com DDD, por exemplo: (73) 99999-9999.';
    else
      update public.commercial_chat_sessions set whatsapp=v_phone,stage='contact_age',lead_score=18,updated_at=now() where id=s.id;
      perform private.lico_sync_lead(s.id);
      v_out:='Qual é a sua idade?';
      v_next:='contact_age';
    end if;

  elsif s.stage='contact_age' then
    begin v_age:=nullif(regexp_replace(v_msg,'\D','','g'),'')::int; exception when others then v_age:=null; end;
    if v_age is null or v_age<12 or v_age>100 then
      v_out:='Preciso da idade em anos para adaptar as perguntas. Ex.: 17 ou 32.';
    else
      update public.commercial_chat_sessions set age=v_age,stage='relationship',lead_score=26,updated_at=now() where id=s.id;
      v_out:='O curso é para você ou para outra pessoa? Responda: 1 Você • 2 Filho(a) • 3 Neto(a) • 4 Irmão/irmã • 5 Cônjuge • 6 Outra pessoa.';
      v_next:='relationship';
    end if;

  elsif s.stage='relationship' then
    v_rel:=case
      when n ~ '(^| )(1|eu|mim|pra mim|para mim|pr[oó]pri[oa])($| )' then 'self'
      when n ~ '(2|filho|filha)' then 'filho'
      when n ~ '(3|neto|neta)' then 'neto'
      when n ~ '(4|irm[aã]o|irma)' then 'irmao'
      when n ~ '(5|marido|esposa|c[oô]njuge|companheir)' then 'conjuge'
      when n ~ '(6|outro|outra|amigo|amiga|parente)' then 'outro' else null end;
    if v_rel is null then
      v_out:='Não consegui identificar. Responda: 1 Você • 2 Filho(a) • 3 Neto(a) • 4 Irmão/irmã • 5 Cônjuge • 6 Outra pessoa.';
    elsif v_rel='self' then
      update public.commercial_chat_sessions
      set relationship='self',student_name=full_name,student_age=age,stage='studies',lead_score=44,updated_at=now()
      where id=s.id;
      v_out:='Você estuda atualmente? Responda sim ou não.'; v_next:='studies';
    else
      update public.commercial_chat_sessions set relationship=v_rel,stage='student_name',lead_score=32,updated_at=now() where id=s.id;
      v_out:='Qual é o nome e sobrenome da pessoa que fará o curso?'; v_next:='student_name';
    end if;

  elsif s.stage='student_name' then
    if not public.lico_valid_name(v_msg) then
      v_out:='Preciso do nome e sobrenome reais da pessoa que fará o curso para continuar.';
    else
      update public.commercial_chat_sessions set student_name=trim(regexp_replace(v_msg,'\s+',' ','g')),stage='student_age',lead_score=38,updated_at=now() where id=s.id;
      v_out:='Qual é a idade dessa pessoa?'; v_next:='student_age';
    end if;

  elsif s.stage='student_age' then
    begin v_age:=nullif(regexp_replace(v_msg,'\D','','g'),'')::int; exception when others then v_age:=null; end;
    if v_age is null or v_age<5 or v_age>100 then
      v_out:='Informe a idade da pessoa que fará o curso em anos.';
    else
      update public.commercial_chat_sessions set student_age=v_age,stage='studies',lead_score=44,updated_at=now() where id=s.id;
      v_out:=coalesce(s.student_name,'Essa pessoa')||' estuda atualmente? Responda sim ou não.'; v_next:='studies';
    end if;

  elsif s.stage='studies' then
    v_bool:=case when n ~ '^(sim|s|claro|positivo)' then true when n ~ '^(n[aã]o|n|negativo)' then false else null end;
    if v_bool is null then
      v_out:='Me responda apenas se estuda atualmente: sim ou não.';
    else
      v_student_age:=coalesce(s.student_age,s.age,99);
      if v_bool and v_student_age<=18 then v_next:='school_level'; v_score:=48;
      elsif v_bool then v_next:='study_shift'; v_score:=52;
      elsif v_student_age<14 then v_next:='availability'; v_score:=70;
      else v_next:='works'; v_score:=56; end if;
      update public.commercial_chat_sessions set studies=v_bool,stage=v_next,lead_score=v_score,updated_at=now() where id=s.id;
      v_out:=case v_next
        when 'school_level' then 'Em qual etapa escolar está: Ensino Fundamental, Ensino Médio, ensino concluído ou outra situação?'
        when 'study_shift' then 'Em qual turno estuda: manhã, tarde, noite ou integral?'
        when 'works' then 'Trabalha atualmente? Responda sim ou não.'
        else 'Em qual período consegue estudar: manhã, tarde, noite, flexível ou EAD?' end;
    end if;

  elsif s.stage='school_level' then
    if length(v_msg)<3 then v_out:='Informe se está no Ensino Fundamental, Ensino Médio, concluído ou outra situação.';
    else
      update public.commercial_chat_sessions set school_level=left(v_msg,120),stage='study_shift',lead_score=52,updated_at=now() where id=s.id;
      v_out:='Em qual turno estuda: manhã, tarde, noite ou integral?'; v_next:='study_shift';
    end if;

  elsif s.stage='study_shift' then
    v_shift:=case when n like '%integral%' then 'integral' when n like '%manh%' then 'manha'
                  when n like '%tarde%' then 'tarde' when n like '%noite%' or n like '%noturn%' then 'noite' else null end;
    if v_shift is null then v_out:='Informe o turno de estudo: manhã, tarde, noite ou integral.';
    else
      v_student_age:=coalesce(s.student_age,s.age,99);
      v_next:=case when v_student_age<14 then 'availability' else 'works' end;
      update public.commercial_chat_sessions set study_shift=v_shift,stage=v_next,lead_score=case when v_next='works' then 56 else 70 end,updated_at=now() where id=s.id;
      v_out:=case when v_next='works' then 'Trabalha atualmente? Responda sim ou não.'
                  else 'Em qual período consegue estudar: manhã, tarde, noite, flexível ou EAD?' end;
    end if;

  elsif s.stage='works' then
    v_bool:=case when n ~ '^(sim|s|claro|positivo)' then true when n ~ '^(n[aã]o|n|negativo)' then false else null end;
    if v_bool is null then v_out:='Me responda se trabalha atualmente: sim ou não.';
    elsif v_bool then
      update public.commercial_chat_sessions set works=true,ever_worked=true,stage='occupation',lead_score=61,updated_at=now() where id=s.id;
      v_out:='Qual é a ocupação ou área de trabalho atual?'; v_next:='occupation';
    else
      update public.commercial_chat_sessions set works=false,stage='ever_worked',lead_score=61,updated_at=now() where id=s.id;
      v_out:='Já trabalhou alguma vez? Responda sim ou não.'; v_next:='ever_worked';
    end if;

  elsif s.stage='occupation' then
    if length(v_msg)<2 then v_out:='Qual é a ocupação ou área em que trabalha atualmente?';
    else
      update public.commercial_chat_sessions set current_occupation=left(v_msg,180),stage='work_schedule',lead_score=65,updated_at=now() where id=s.id;
      v_out:='Qual é o horário de trabalho? Ex.: segunda a sexta, 08:00 às 18:00.'; v_next:='work_schedule';
    end if;

  elsif s.stage='work_schedule' then
    if length(v_msg)<3 then v_out:='Informe o horário de trabalho para eu cruzar com as turmas disponíveis.';
    else
      update public.commercial_chat_sessions set work_schedule=left(v_msg,240),stage='availability',lead_score=70,updated_at=now() where id=s.id;
      v_out:='Em qual período consegue estudar: manhã, tarde, noite, flexível ou EAD? Se tiver horário exato, pode informar.'; v_next:='availability';
    end if;

  elsif s.stage='ever_worked' then
    v_bool:=case when n ~ '^(sim|s|claro|positivo)' then true when n ~ '^(n[aã]o|n|negativo)' then false else null end;
    if v_bool is null then v_out:='Me responda se já trabalhou alguma vez: sim ou não.';
    elsif v_bool then
      update public.commercial_chat_sessions set ever_worked=true,stage='previous_experience',lead_score=65,updated_at=now() where id=s.id;
      v_out:='Em qual área foi a experiência profissional mais recente?'; v_next:='previous_experience';
    else
      update public.commercial_chat_sessions set ever_worked=false,stage='availability',lead_score=70,updated_at=now() where id=s.id;
      v_out:='Em qual período consegue estudar: manhã, tarde, noite, flexível ou EAD?'; v_next:='availability';
    end if;

  elsif s.stage='previous_experience' then
    if length(v_msg)<2 then v_out:='Em qual área foi a experiência mais recente?';
    else
      update public.commercial_chat_sessions
      set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('previous_experience',left(v_msg,180)),
          stage='availability',lead_score=70,updated_at=now()
      where id=s.id;
      v_out:='Em qual período consegue estudar: manhã, tarde, noite, flexível ou EAD?'; v_next:='availability';
    end if;

  elsif s.stage='availability' then
    v_period:=case when n ~ '(ead|online|casa)' then 'ead'
                   when n ~ '(flex|qualquer|indiferente)' then 'flexivel'
                   when n ~ '(noite|noturn)' then 'noite'
                   when n like '%tarde%' then 'tarde'
                   when n like '%manh%' then 'manha' else null end;
    if v_period is null then v_out:='Informe o período disponível: manhã, tarde, noite, flexível ou EAD.';
    elsif v_period='noite' then
      update public.commercial_chat_sessions set availability=v_msg,availability_period='noite',stage='night_confirm',lead_score=74,updated_at=now() where id=s.id;
      v_out:='Para curso presencial à noite, a Live Connect trabalha somente na quarta-feira, das 18:00 às 20:00. Esse horário funciona?';
      v_next:='night_confirm';
    else
      update public.commercial_chat_sessions set availability=v_msg,availability_period=v_period,stage='objective',lead_score=80,updated_at=now() where id=s.id;
      v_out:=private.lico_objective_prompt(s.id); v_next:='objective';
    end if;

  elsif s.stage='night_confirm' then
    v_bool:=case when n ~ '^(sim|s|claro|funciona|consigo|ok)' then true when n ~ '^(n[aã]o|n|nao consigo|não consigo)' then false else null end;
    if v_bool is null then v_out:='Para presencial à noite, preciso confirmar: quarta-feira, 18:00 às 20:00 funciona? Responda sim ou não.';
    elsif v_bool then
      update public.commercial_chat_sessions set night_slot_confirmed=true,stage='objective',lead_score=80,updated_at=now() where id=s.id;
      v_out:=private.lico_objective_prompt(s.id); v_next:='objective';
    else
      update public.commercial_chat_sessions
      set night_slot_confirmed=false,availability=null,availability_period=null,stage='availability',
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('night_rejected',true),updated_at=now()
      where id=s.id;
      v_out:='Sem problema. O presencial noturno é somente quarta-feira, 18:00 às 20:00. Podemos avaliar manhã, tarde, um horário flexível ou EAD. Qual alternativa funciona melhor?';
      v_next:='availability';
    end if;

  elsif s.stage='objective' then
    v_student_age:=coalesce(s.student_age,s.age,99);
    if length(v_msg)<4 then v_out:=private.lico_objective_prompt(s.id);
    elsif v_student_age between 14 and 18 and not coalesce(s.works,false) and not coalesce(s.ever_worked,false)
          and n ~ 'mudar.*[aá]rea' then
      v_out:='Como ainda não houve experiência profissional, “mudar de área” não descreve bem o momento. Vou ajustar: o foco é primeiro emprego, currículo, descoberta de área, habilidade específica ou Jovem Aprendiz. Qual desses objetivos representa melhor?';
    else
      update public.commercial_chat_sessions set objective=left(v_msg,600),stage='timeline',lead_score=85,updated_at=now() where id=s.id;
      v_out:='Quando pretende começar? 1 Hoje/agora • 2 Nesta semana • 3 Neste mês • 4 Ainda estou pesquisando.'; v_next:='timeline';
    end if;

  elsif s.stage='timeline' then
    v_timeline:=case when n ~ '(hoje|agora|imediat|^1$)' then 'hoje'
                     when n ~ '(semana|^2$)' then 'esta_semana'
                     when n ~ '(m[eê]s|30 dias|^3$)' then 'este_mes'
                     when n ~ '(pesquis|sem pressa|futuro|^4$)' then 'pesquisando' else null end;
    if v_timeline is null then v_out:='Quando pretende começar? 1 Hoje/agora • 2 Nesta semana • 3 Neste mês • 4 Ainda estou pesquisando.';
    else
      update public.commercial_chat_sessions set start_timeline=v_timeline,stage='decision_factor',lead_score=89,updated_at=now() where id=s.id;
      v_student_age:=coalesce(s.student_age,s.age,99);
      v_out:=case when v_student_age<=18 and not coalesce(s.works,false) and not coalesce(s.ever_worked,false)
        then 'Na escolha da formação, o que mais importa: 1 Aprendizado prático • 2 Horário • 3 Preparação para emprego/Jovem Aprendiz • 4 Duração • 5 Certificado • 6 Preço?'
        else 'O que mais pesa na decisão: 1 Preço • 2 Horário • 3 Duração • 4 Empregabilidade • 5 Conteúdo • 6 Certificado?' end;
      v_next:='decision_factor';
    end if;

  elsif s.stage='decision_factor' then
    v_factor:=case when n ~ '(pre[cç]o|valor|mensal|or[cç]amento|^1$)' then 'preco'
                   when n ~ '(hor[aá]rio|turno|tempo|^2$)' then 'horario'
                   when n ~ '(dura[cç][aã]o|r[aá]pido|^3$)' then 'duracao'
                   when n ~ '(emprego|trabalho|mercado|vaga|^4$)' then 'empregabilidade'
                   when n ~ '(conte[uú]do|aula|grade|^5$)' then 'conteudo'
                   when n ~ '(certificado|^6$)' then 'certificado' else null end;
    if v_factor is null then v_out:='Escolha a prioridade principal pelo número ou escreva: preço, horário, duração, empregabilidade, conteúdo ou certificado.';
    else
      v_student_age:=coalesce(s.student_age,s.age,99);
      v_need_authority:=(coalesce(s.relationship,'self')<>'self' or v_student_age<18);
      if v_need_authority then
        update public.commercial_chat_sessions set decision_factor=v_factor,stage='decision_authority',lead_score=92,updated_at=now() where id=s.id;
        v_out:='Você participa da decisão e consegue autorizar a matrícula dessa pessoa? Responda sim ou não.'; v_next:='decision_authority';
      else
        update public.commercial_chat_sessions set decision_factor=v_factor,decision_authority=true,stage='course',lead_score=95,updated_at=now() where id=s.id;
        v_courses:=private.lico_recommend_courses(s.id);
        v_out:='Com base no perfil, idade, objetivo e disponibilidade, estas opções fazem mais sentido:'||E'\n\n'||v_courses||E'\n\nQual delas mais interessa?';
        v_next:='course';
      end if;
    end if;

  elsif s.stage='decision_authority' then
    v_bool:=case when n ~ '^(sim|s|claro|consigo|autorizo|positivo)' then true when n ~ '^(n[aã]o|n|negativo)' then false else null end;
    if v_bool is null then v_out:='Preciso saber se você participa da decisão e consegue autorizar a matrícula. Responda sim ou não.';
    elsif not v_bool then
      update public.commercial_chat_sessions set decision_authority=false,status='handoff',stage='handoff',updated_at=now() where id=s.id;
      v_out:='Entendi. Como a decisão depende de outra pessoa, vou encaminhar para o Comercial orientar a melhor forma de continuar.';
      v_next:='handoff';
    else
      update public.commercial_chat_sessions set decision_authority=true,stage='course',lead_score=95,updated_at=now() where id=s.id;
      v_courses:=private.lico_recommend_courses(s.id);
      v_out:='Ótimo. Pelo perfil informado, estas formações são as mais compatíveis:'||E'\n\n'||v_courses||E'\n\nQual delas mais interessa?';
      v_next:='course';
    end if;

  elsif s.stage='course' then
    begin v_idx:=case when v_msg ~ '^\s*\d+\s*$' then trim(v_msg)::int else null end; exception when others then v_idx:=null; end;
    if v_idx is not null then
      select e into v_course
      from jsonb_array_elements(coalesce(s.metadata->'suggested_courses','[]'::jsonb)) with ordinality a(e,ord)
      where ord=v_idx limit 1;
    else
      select e into v_course
      from jsonb_array_elements(coalesce(s.metadata->'suggested_courses','[]'::jsonb)) a(e)
      where lower(e->>'name')=n or lower(e->>'name') like '%'||n||'%' or n like '%'||lower(e->>'name')||'%'
      limit 1;
    end if;
    if v_course is null then
      select jsonb_build_object('id',c.id,'name',c.name,'type',c.type::text) into v_course
      from public.courses c where c.active=true and lower(c.name) like '%'||n||'%' order by c.name limit 1;
    end if;
    if v_course is null then
      v_out:='Ainda não consegui identificar a formação. Escolha pelo número da lista ou escreva o nome do curso.';
    else
      v_course_id:=(v_course->>'id')::uuid;
      select cl.* into v_class
      from public.class_capacity_summary cl
      where cl.course_id=v_course_id and cl.status='aberta' and coalesce(cl.source_hidden,false)=false and cl.remaining_seats>0
        and (
          s.availability_period in ('flexivel','ead') or s.availability_period is null
          or (s.availability_period='manha' and cl.start_time<'12:00'::time)
          or (s.availability_period='tarde' and cl.start_time>='12:00'::time and cl.start_time<'17:00'::time)
          or (s.availability_period='noite' and cl.weekday=3 and cl.start_time='18:00'::time)
        )
      order by cl.weekday,cl.start_time limit 1;

      if s.availability_period='noite' and v_class.id is null then
        v_out:='Para presencial à noite, só trabalhamos na quarta-feira das 18:00 às 20:00, e não encontrei vaga compatível para '||(v_course->>'name')||' nessa janela agora. Escolha outra formação, outro período ou peça um consultor.';
      elsif s.availability_period in ('manha','tarde') and v_class.id is null then
        update public.commercial_chat_sessions set stage='availability',availability=null,availability_period=null,updated_at=now() where id=s.id;
        v_out:='Não encontrei turma com vaga nesse período para '||(v_course->>'name')||'. Informe outro período, escolha EAD/flexível ou peça um consultor.';
        v_next:='availability';
      else
        update public.commercial_chat_sessions set
          course_interest=v_course->>'name',course_type=v_course->>'type',
          preferred_class_id=case when v_class.id is null then null else v_class.id end,
          preferred_schedule=case when v_class.id is null then null else
            case v_class.weekday when 1 then 'Segunda-feira' when 2 then 'Terça-feira' when 3 then 'Quarta-feira'
              when 4 then 'Quinta-feira' when 5 then 'Sexta-feira' when 6 then 'Sábado' else 'Dia' end
            ||' • '||to_char(v_class.start_time,'HH24:MI')||' às '||to_char(v_class.end_time,'HH24:MI') end,
          status='qualified',stage='email',lead_score=97,updated_at=now()
        where id=s.id;
        v_out:=(v_course->>'name')||' combina com o perfil informado.'
          ||case when v_class.id is not null then ' Encontrei uma turma compatível: '||
            case v_class.weekday when 1 then 'Segunda-feira' when 2 then 'Terça-feira' when 3 then 'Quarta-feira'
              when 4 then 'Quinta-feira' when 5 then 'Sexta-feira' when 6 then 'Sábado' else 'Dia' end
            ||' • '||to_char(v_class.start_time,'HH24:MI')||' às '||to_char(v_class.end_time,'HH24:MI')||'.' else '' end
          ||E'\n\nPara adiantar a matrícula e o acesso ao curso, qual e-mail deve ser usado?';
        v_next:='email';
      end if;
    end if;

  elsif s.stage='email' then
    if v_msg !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      v_out:='Preciso de um e-mail válido para adiantar o cadastro e o acesso ao curso. Ex.: nome@email.com.';
    else
      update public.commercial_chat_sessions
      set email=lower(v_msg),qualification_completed_at=now(),status='qualified',stage='closing',lead_score=99,updated_at=now()
      where id=s.id;
      v_lead:=private.lico_sync_lead(s.id);
      select * into s from public.commercial_chat_sessions where id=s.id;
      select c.id into v_course_id from public.courses c where c.active=true and lower(c.name)=lower(s.course_interest) limit 1;
      if v_lead is not null and v_course_id is not null then
        if not exists(select 1 from public.lead_interests li where li.lead_id=v_lead and li.course_id=v_course_id and li.source='portal_chatbot') then
          insert into public.lead_interests(lead_id,course_id,interest_type,source,metadata)
          select v_lead,v_course_id,case when c.type='gratuito' then 'curso_gratuito' else 'curso_pago' end,'portal_chatbot',
            jsonb_build_object('chat_session_id',s.id,'relationship',s.relationship,'student_age',coalesce(s.student_age,s.age),
              'studies',s.studies,'study_shift',s.study_shift,'works',s.works,'ever_worked',s.ever_worked,
              'availability',s.availability,'availability_period',s.availability_period,'objective',s.objective,
              'start_timeline',s.start_timeline,'decision_factor',s.decision_factor,'preferred_schedule',s.preferred_schedule)
          from public.courses c where c.id=v_course_id;
        end if;
        insert into public.lead_activities(lead_id,activity_type,description,metadata)
        values(v_lead,'lico_lead_qualificado','Lico — lead qualificado para '||s.course_interest,
          jsonb_build_object('chat_session_id',s.id,'lead_score',99,'availability',s.availability,'objective',s.objective));
      end if;
      select coalesce(c.offer_text,c.title) into v_offer
      from public.campaigns c
      where c.active=true and c.highlight_public=true
        and (c.start_date is null or c.start_date<=current_date)
        and (c.end_date is null or c.end_date>=current_date)
      order by c.priority desc,c.created_at desc limit 1;
      v_out:='Perfil qualificado:'||E'\n• '||coalesce(s.student_name,s.full_name)||' • '||coalesce(s.student_age,s.age)::text||' anos'
        ||E'\n• '||case when s.studies then 'Estuda'||coalesce(' • turno '||s.study_shift,'') else 'Não estuda atualmente' end
        ||E'\n• '||case when s.works then 'Trabalha'||coalesce(' • '||s.current_occupation,'') else
          case when s.ever_worked then 'Não trabalha atualmente • já teve experiência' else 'Sem experiência profissional informada' end end
        ||E'\n• Disponibilidade: '||case when s.availability_period='noite' then 'Noite • quarta-feira, 18:00 às 20:00' else coalesce(s.availability,s.availability_period,'a confirmar') end
        ||E'\n• Objetivo: '||coalesce(s.objective,'—')
        ||E'\n• Curso: '||coalesce(s.course_interest,'—')
        ||coalesce(E'\n• Turma compatível: '||s.preferred_schedule,'')
        ||case when v_offer is not null then E'\n\n'||v_offer else '' end
        ||E'\n\nEstá tudo qualificado. Quer iniciar a matrícula agora?';
      perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage','closing','assistant','Lico','qualified',true));
      return jsonb_build_object('ok',true,'token',p_token,'stage','closing','message',v_out,'qualified',true,'lead_score',99);
    end if;

  elsif s.stage='closing' then
    if n ~ '^(sim|s|quero|vamos|pode|agora|continuar|prosseguir|matricul|fechar)' then
      if s.availability_period='noite' and not coalesce(s.night_slot_confirmed,false) then
        update public.commercial_chat_sessions set stage='night_confirm',updated_at=now() where id=s.id;
        v_out:='Antes da matrícula preciso confirmar o horário: presencial à noite é somente quarta-feira, 18:00 às 20:00. Esse horário funciona?';
        v_next:='night_confirm';
      elsif nullif(s.course_interest,'') is null or nullif(s.email,'') is null then
        v_next:=case when nullif(s.course_interest,'') is null then 'course' else 'email' end;
        update public.commercial_chat_sessions set stage=v_next,updated_at=now() where id=s.id;
        v_out:='Ainda falta uma informação obrigatória da qualificação. Vou retomar de onde paramos.';
      else
        update public.commercial_chat_sessions set status='closing',stage='enrollment',lead_score=100,updated_at=now() where id=s.id;
        v_lead:=private.lico_sync_lead(s.id);
        if v_lead is not null then
          insert into public.lead_activities(lead_id,activity_type,description,metadata)
          values(v_lead,'lico_fechamento_iniciado','Lico — matrícula iniciada — '||s.course_interest,
            jsonb_build_object('chat_session_id',s.id,'preferred_class_id',s.preferred_class_id,'preferred_schedule',s.preferred_schedule));
        end if;
        v_link:='https://www.liveconnect.com.br/cursos/'||public.lico_slugify(s.course_interest)
          ||'/?utm_source=lico&utm_medium=chat&utm_campaign=matricula_lico&chat='||p_token::text;
        v_out:='Perfeito. Sua qualificação está concluída. Vou abrir a matrícula com os dados que já coletei; você só completa os documentos e confirma as preferências finais.';
        perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage','enrollment','assistant','Lico','cta_url',v_link,'cta_label','Iniciar matrícula'));
        return jsonb_build_object('ok',true,'token',p_token,'stage','enrollment','message',v_out,
          'cta',jsonb_build_object('label','Iniciar matrícula','url',v_link),'qualified',true,'lead_score',100);
      end if;
    else
      if n ~ '(pre[cç]o|valor|mensal)' then
        select coalesce(c.offer_text,c.title) into v_offer
        from public.campaigns c where c.active=true and c.highlight_public=true
          and (c.start_date is null or c.start_date<=current_date) and (c.end_date is null or c.end_date>=current_date)
        order by c.priority desc,c.created_at desc limit 1;
        v_out:=coalesce(v_offer,'A condição depende da oferta vigente no sistema.')||' Isso resolve sua dúvida para avançarmos com a matrícula?';
      elsif n ~ '(hor[aá]rio|turno)' then
        v_out:=case when s.availability_period='noite'
          then 'Para presencial à noite, o horário é exclusivamente quarta-feira, 18:00 às 20:00. Esse horário funciona para você?'
          else 'Sua disponibilidade registrada é '||coalesce(s.availability,s.availability_period,'a confirmar')||'. Quer avançar com a matrícula?' end;
      elsif n ~ '(curso|d[uú]vida|conte[uú]do)' then
        v_out:='Posso chamar o Comercial para detalhar '||coalesce(s.course_interest,'a formação')||', ou podemos seguir para a matrícula. O que prefere?';
      else
        v_out:='Entendi. Para eu não forçar uma decisão, me diga o principal motivo que ainda impede a matrícula: valor, horário, curso, tempo ou necessidade de falar com outra pessoa.';
      end if;
    end if;
  else
    v_out:='Vamos continuar sua qualificação. Responda à última pergunta para eu avançar com segurança.';
  end if;

  if v_next is null then v_next:=coalesce((select stage from public.commercial_chat_sessions where id=s.id),s.stage); end if;
  if v_phone is not null or v_next in ('studies','school_level','study_shift','works','occupation','work_schedule','ever_worked',
      'previous_experience','availability','night_confirm','objective','timeline','decision_factor','decision_authority','course','email','closing') then
    perform private.lico_sync_lead(s.id);
  end if;
  perform private.lico_append(s.id,'assistant',v_out,jsonb_build_object('stage',v_next,'assistant','Lico'));
  select * into s from public.commercial_chat_sessions where id=s.id;
  return jsonb_build_object('ok',true,'token',p_token,'stage',v_next,'message',v_out,
    'lead_score',coalesce(s.lead_score,0),'handoff',(v_next='handoff'));
end $$;

revoke all on function public.portal_lico_chat(text,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.portal_lico_chat(text,uuid,text,jsonb) to service_role;
revoke all on function public.lico_valid_name(text) from public,anon;
revoke all on function public.lico_slugify(text) from public,anon;
